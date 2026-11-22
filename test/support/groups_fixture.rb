# frozen_string_literal: true

require_relative "ledger_commands"

# A ledger of six pieces for test/browser/groups.cjs: P1 to P3 await a
# commit and a merge, P4 to P6 await their start, so the page offers two
# group buttons. Made by bin/ledger's words in the caller's journal, in
# one transaction.
module GroupsFixture
    GOAL = ["--goal", "two sets of pieces await the same words",
            "--title", "Two groups waiting", "--short", "two groups",
            "--date", "2026-11-19"].freeze
    PIECE = ["--route", "sonnet, effort: low", "--problem", "the fix waits",
             "--risk", "2/10 — the fix waits; nothing breaks",
             "--plan", "go", "--no-picture", "a rename"].freeze
    DONE = ["--status", "verified", "--verified-by", "me",
            "--evidence", "suite green"].freeze
    TITLES = ["fix the reorder", "fix the header", "fix the footer",
              "fix the menu", "fix the search", "fix the login"].freeze

    def self.build(journal, address)
        run = lambda do |word, *args|
            LedgerCommands.run(journal, word, address, *args)
        end
        journal.transaction do
            run.call("new", *GOAL)
            TITLES.each_with_index { |title, i| piece(run, title, i) }
        end
    end

    def self.piece(run, title, index)
        first = index < 3
        run.call("piece", "new", *PIECE, *(first ? DONE : []),
                 "--title", title)
        run.call("piece", "P#{index + 1}", "--awaits",
                 first ? "commit, merge" : "start")
    end
end
