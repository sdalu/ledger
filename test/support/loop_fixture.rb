# frozen_string_literal: true

require_relative "ledger_commands"

# A ledger of two questions for test/browser/loop.cjs: O1 asked by P1,
# which awaits the user's start (a loop the commands refuse, so the
# awaits row is written beside them), and O2 asked by P2, a planned piece
# that awaits nothing. Made by bin/ledger's words in the caller's
# journal, in one transaction.
module LoopFixture
    GOAL = ["--goal", "a question waits on a piece that waits on the user",
            "--title", "Question and piece", "--short", "a loop",
            "--date", "2026-11-19"].freeze

    CHOICES = ["A = the short name | B = the long name",
               "C = the old flag | D = the new flag"].freeze

    def self.build(journal, address)
        run = lambda do |word, *args|
            LedgerCommands.run(journal, word, address, *args)
        end
        journal.transaction do
            run.call("new", *GOAL)
            2.times { piece(run) }
            2.times { |at| question(run, at + 1) }
            hold(journal)
        end
    end

    def self.piece(run)
        run.call("piece", "new", "--route", "sonnet, effort: low",
                 "--title", "build what the question picks",
                 "--problem", "the build waits on the choice",
                 "--risk", "2/10 — a redo")
    end

    def self.question(run, number)
        run.call("ask", "which tool number #{number}?",
                 "--title", "Tool choice #{number}",
                 "--problem", "two tools", "--risk", "3/10 — rework",
                 "--choices", CHOICES.fetch(number - 1),
                 "--recommend", "A, it is shorter", "--by", "P#{number}",
                 "--no-picture", "a choice of words")
    end

    # P1 of the ledger just made (the newest) awaits start, written past
    # the commands that refuse the loop.
    def self.hold(journal)
        ledger = journal.db[:ledgers].max(:id)
        id = journal.db[:pieces].where(ledger_id: ledger, n: 1).get(:id)
        journal.db[:piece_awaits].insert(piece_id: id, position: 0,
                                         word: "start")
    end
end
