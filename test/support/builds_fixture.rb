# frozen_string_literal: true

require_relative "ledger_commands"

# A ledger of one question and the piece building it, for test/browser/
# builds.cjs: O1 with options A and B; P2 awaits its start and builds
# O1 (piece --builds), P1 is obsolete, replaced by P2. Made by
# bin/ledger's words in the caller's journal, in one transaction.
module BuildsFixture
    GOAL = ["--goal", "one card answers and starts", "--title",
            "Answer and start", "--short", "answer and start",
            "--date", "2026-11-22"].freeze
    QUESTION = ["which lexer?", "--title", "Lexer choice",
                "--problem", "two lexers are on the table",
                "--risk", "3/10 — a rewrite",
                "--choices", "A = hand-written | B = generated",
                "--recommend", "A, fewer tools",
                "--no-picture", "a choice of words"].freeze
    PIECE = ["new", "--route", "sonnet, effort: low", "--awaits", "start",
             "--problem", "the lexer waits for a go",
             "--risk", "4/10 — a wrong lexer", "--no-picture",
             "no screen"].freeze

    def self.build(journal, address)
        run = lambda do |word, *args|
            LedgerCommands.run(journal, word, address, *args)
        end
        journal.transaction do
            run.call("new", *GOAL)
            run.call("ask", *QUESTION)
            pieces(run)
        end
    end

    def self.pieces(run)
        run.call("piece", *PIECE, "--title", "write the old lexer")
        run.call("piece", *PIECE, "--title", "write the lexer",
                 "--plan", "the lexer the answer picks", "--builds", "O1")
        run.call("piece", "P1", "--status", "obsolete", "--obsoleted-by", "P2")
    end
end
