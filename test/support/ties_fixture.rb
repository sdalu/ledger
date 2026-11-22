# frozen_string_literal: true

require_relative "ledger_commands"

# A ledger of pieces and questions, for test/browser/ties.cjs: P1 waits
# for P2, P3 is obsolete, replaced by P4, P5 builds the open question O1,
# P6 awaits the user's word, P7 waits for P5 and P6, P8 builds the
# answered question O2, P9 is verified, P10 waits for it. Made by
# bin/ledger's words in the caller's journal, in one transaction.
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
    SECOND = ["which parser?", "--title", "Parser choice",
              "--problem", "two parsers are on the table",
              "--risk", "3/10 — a rewrite",
              "--choices", "A = recursive descent | B = table driven",
              "--recommend", "A, readable",
              "--no-picture", "a choice of words"].freeze
    ANSWER = "\"A = recursive descent\" — readable"
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
            run.call("ask", *SECOND)
            pieces(run)
            run.call("answer", "O2", "--decision", ANSWER)
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
        later(run)
        run.call("piece", "P1", "--after", "P2")
        run.call("piece", "P3", "--status", "obsolete", "--obsoleted-by", "P4")
    end

    # P6 awaits a word, P7 waits for P5 and P6, P8 builds O2, P9 is
    # verified, P10 waits for it.
    def self.later(run)
        run.call("piece", "new", *ROUTE, *BUILDER, "--title", "write the docs")
        run.call("piece", "new", *ROUTE, "--title", "write the tests",
                 "--after", "P5,P6")
        run.call("piece", "new", *ROUTE, *BUILDER, "--title",
                 "write the parser", "--builds", "O2")
        run.call("piece", "new", *ROUTE, "--title", "write the spec",
                 "--status", "verified", "--verified-by", "me",
                 "--evidence", "it reads")
        run.call("piece", "new", *ROUTE, "--title", "write the manual",
                 "--after", "P9")
    end
end
