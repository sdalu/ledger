# frozen_string_literal: true

require "fileutils"

require_relative "browser_fixture"
require_relative "ledger_commands"

# A ledger of seven pieces waiting on the user's word to commit, rated
# in no order of their age (3, 9, unrated, 5, 7, 2, 4), and one question
# rated 8, for test/browser/risk.cjs: the oldest wait is P1, the highest
# risk P2. Made by bin/ledger's words in the caller's journal, in one
# transaction.
module RiskFixture
    GOAL = ["--goal", "seven pieces wait for a commit",
            "--title", "Rated waiting pieces", "--short", "rated pieces",
            "--date", "2026-11-19"].freeze
    # The risk of P1 to P7; nil leaves the piece unrated.
    RATINGS = [3, 9, nil, 5, 7, 2, 4].freeze
    QUESTION = ["which name does the tool take?",
                "--title", "Tool name", "--problem", "two names are in use",
                "--risk", "8/10 — scripts call the old one",
                "--choices", "A = the short name | B = the long name",
                "--recommend", "A, it is shorter",
                "--no-picture", "a choice of words"].freeze

    def self.build(journal, address)
        run = lambda do |word, *args|
            LedgerCommands.run(journal, word, address, *args)
        end
        dir = File.join(File.dirname(address), "pictures")
        journal.transaction do
            run.call("new", *GOAL)
            pieces(run, journal, dir)
            run.call("ask", *QUESTION)
        end
    end

    def self.pieces(run, journal, dir)
        RATINGS.each_with_index do |rating, at|
            piece(run, journal, at + 1, rating, dir)
        end
    end

    def self.piece(run, journal, number, rating, dir)
        risk = ["--risk", "#{rating || 0}/10 — the fix waits"]
        run.call("piece", "new", "--route", "sonnet, effort: low",
                 "--title", "fix the reorder number #{number}",
                 "--problem", "the fix is ready, not committed", *risk,
                 "--plan", "commit it", "--status", "verified",
                 "--verified-by", "me", "--evidence", "suite green")
        pictures(run, "P#{number}", dir)
        run.call("piece", "P#{number}", "--awaits", "commit")
        unrate(journal, number) unless rating
    end

    # The commands refuse a piece awaiting a word without a rating, a
    # ledger of older words may hold one: the row is written unrated.
    def self.unrate(journal, number)
        journal.db[:pieces].where(title: "fix the reorder number #{number}")
               .update(risk: "not rated", risk_rating: nil)
    end

    # The before and after a piece awaiting a word must carry, copies
    # under the piece's own names: a ledger refuses one picture twice.
    def self.pictures(run, id, dir)
        FileUtils.mkdir_p(dir)
        %w[before after].each do |role|
            file = File.join(dir, "#{id}-#{role}.svg")
            FileUtils.cp(File.join(BrowserFixture::MOCKUPS,
                                   "reorder-#{role}.svg"), file)
            run.call("mockup", file, "--piece", id, "--#{role}")
        end
    end
end
