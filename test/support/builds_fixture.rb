# frozen_string_literal: true

require_relative "ledger_commands"

# A ledger of two questions, each with the piece building it, for
# test/browser/builds.cjs: O1 and O2 with options A and B; P2 awaits its
# start and builds O1 (piece --builds), P3 builds O2, P1 is obsolete,
# replaced by P2. Made by bin/ledger's words in the caller's journal, in
# one transaction.
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
    SECOND = ["which parser?", "--title", "Parser choice",
              "--problem", "two parsers are on the table",
              "--risk", "3/10 — a rewrite",
              "--choices", "A = recursive descent | B = table driven",
              "--recommend", "A, readable",
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
            run.call("ask", *SECOND)
            pieces(run)
        end
    end

    def self.pieces(run)
        run.call("piece", *PIECE, "--title", "write the old lexer")
        run.call("piece", *PIECE, "--title", "write the lexer",
                 "--plan", "the lexer the answer picks", "--builds", "O1")
        run.call("piece", "P1", "--status", "obsolete", "--obsoleted-by", "P2")
        run.call("piece", *PIECE, "--title", "write the parser",
                 "--plan", "the parser the answer picks", "--builds", "O2")
    end
end
