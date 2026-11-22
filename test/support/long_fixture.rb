# frozen_string_literal: true

require "fileutils"

require_relative "browser_fixture"
require_relative "ledger_commands"

# A ledger of twelve pieces, each waiting on the user's word to commit:
# a page long enough that the next card after a word is a scroll away,
# for test/browser/long.cjs. Made by bin/ledger's words in the caller's
# journal, in one transaction.
module LongFixture
    COUNT = 12
    GOAL = ["--goal", "twelve pieces wait for a commit",
            "--title", "Twelve waiting pieces", "--short", "twelve pieces",
            "--date", "2026-11-19"].freeze

    def self.build(journal, address)
        run = lambda do |word, *args|
            LedgerCommands.run(journal, word, address, *args)
        end
        dir = File.join(File.dirname(address), "pictures")
        journal.transaction do
            run.call("new", *GOAL)
            (1..COUNT).each { piece(run, it, dir) }
        end
    end

    def self.piece(run, number, dir)
        id = "P#{number}"
        run.call("piece", "new", "--route", "sonnet, effort: low",
                 "--title", "fix the reorder number #{number}",
                 "--problem", "the fix is ready, not committed",
                 "--risk", "2/10 — the fix waits; nothing breaks",
                 "--plan", "commit it", "--status", "verified",
                 "--verified-by", "me", "--evidence", "suite green")
        pictures(run, id, dir)
        run.call("piece", id, "--awaits", "commit")
    end

    # The before and after a piece awaiting a word must carry.
    # A ledger refuses one picture twice, so each piece gets copies under
    # its own names, beside the ledger.
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
