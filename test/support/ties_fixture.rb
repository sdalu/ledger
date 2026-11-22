# frozen_string_literal: true

require_relative "ledger_commands"

# A ledger of five pieces and a question, for test/browser/ties.cjs: P1
# waits for P2, P3 is obsolete, replaced by P4, P5 builds the open
# question O1. Made by bin/ledger's words in the caller's journal, in one
# transaction.
module TiesFixture
    GOAL = ["--goal", "pieces tied to each other", "--title",
            "Tied pieces", "--short", "tied pieces",
            "--date", "2026-11-22"].freeze
    QUESTION = ["which lexer?", "--title", "Lexer choice",
                "--problem", "two lexers are on the table",
                "--risk", "3/10 — a rewrite",
                "--choices", "A = hand-written | B = generated",
                "--recommend", "A, fewer tools",
                "--no-picture", "a choice of words"].freeze
    ROUTE = ["--route", "sonnet, effort: low"].freeze
    BUILDER = ["--awaits", "start", "--problem", "the lexer waits for a go",
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
        ["the parser", "the tables", "the old grammar",
         "the grammar"].each do |name|
            run.call("piece", "new", *ROUTE, "--title", "write #{name}")
        end
        run.call("piece", "new", *ROUTE, *BUILDER, "--title",
                 "write the lexer", "--plan", "the lexer the answer picks",
                 "--builds", "O1")
        run.call("piece", "P1", "--after", "P2")
        run.call("piece", "P3", "--status", "obsolete", "--obsoleted-by", "P4")
    end
end
