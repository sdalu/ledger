# frozen_string_literal: true

require_relative "ledger_commands"

# A ledger for test/browser/live.cjs, whose checks change it from
# outside while its page is open: three planned pieces (so the order
# form shows), and two questions waiting on the user, O1 and O2, each
# answered once by a send. Made by bin/ledger's words in the caller's
# journal, in one transaction.
module LiveFixture
    GOAL = ["--goal", "the page follows the ledger in place",
            "--title", "Live page", "--short", "drawn in place",
            "--date", "2026-11-19"].freeze

    CHOICES = ["A = the short name | B = the long name",
               "A = the old name | B = the new name"].freeze

    def self.build(journal, address)
        run = lambda do |word, *args|
            LedgerCommands.run(journal, word, address, *args)
        end
        journal.transaction do
            run.call("new", *GOAL)
            %w[first second third].each { piece(run, it) }
            [1, 2].each { question(run, it) }
        end
    end

    def self.piece(run, name)
        run.call("piece", "new", "--route", "sonnet, effort: low",
                 "--title", "the #{name} piece",
                 "--problem", "a part of the page",
                 "--risk", "2/10 — a redo")
    end

    def self.question(run, number)
        run.call("ask", "which name number #{number}?",
                 "--title", "Name choice #{number}",
                 "--problem", "two names", "--risk", "2/10 — a rename",
                 "--choices", CHOICES.fetch(number - 1),
                 "--recommend", "A, it is shorter",
                 "--no-picture", "a choice of words")
    end
end
