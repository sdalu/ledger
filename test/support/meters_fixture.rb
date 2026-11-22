# frozen_string_literal: true

require "fileutils"

require_relative "ledger_commands"

# Two pieces waiting on the user's word, for test/browser/meters.cjs: P1
# dispatched (its dispatch rates the work 6/10, its own --risk 3/10),
# irreversible, awaiting commit and push; P2 kept, rated 7/10, awaiting
# deploy. Made by bin/ledger's words in the caller's journal, in one
# transaction.
module MetersFixture
    GOAL = ["--goal", "two pieces wait for a word", "--title",
            "Step and work", "--short", "step and work",
            "--date", "2026-11-22"].freeze
    DISPATCHED = ["new", "--title", "Rename the reorder helper", "--route",
                  "sonnet, effort: low", "--status", "verified",
                  "--verified-by", "me", "--evidence", "suite green",
                  "--problem", "the rename is not committed",
                  "--risk", "3/10 — a caller missed", "--plan", "commit it",
                  "--no-picture", "a rename"].freeze
    KEPT = ["new", "--title", "Deploy the viewer", "--status",
            "kept: the main session deploys", "--problem",
            "the build is not live", "--risk",
            "7/10 — a failed restart cuts the viewer", "--plan", "deploy it",
            "--no-picture", "a deploy", "--awaits", "deploy"].freeze
    ANNOUNCE = "ANNOUNCE\nWHAT: rename the helper\nWHY: mechanical\n" \
               "WHICH: sonnet, effort: low\n" \
               "RISK: 6/10 — a missed caller breaks the reorder\n" \
               "MODE: attended\n"

    def self.build(journal, address)
        run = lambda do |word, *args|
            LedgerCommands.run(journal, word, address, *args)
        end
        journal.transaction do
            run.call("new", *GOAL)
            dispatched(run, address)
            run.call("piece", *KEPT)
        end
    end

    # P1: announced, then given its words and marked irreversible.
    def self.dispatched(run, address)
        run.call("piece", *DISPATCHED)
        run.call("piece", "P1", "--announce", announce(address))
        run.call("piece", "P1", "--awaits", "commit, push", "--irreversible")
    end

    def self.announce(address)
        file = File.join(File.dirname(address), "announce.txt")
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, ANNOUNCE)
        file
    end
end
