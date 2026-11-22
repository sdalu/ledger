# frozen_string_literal: true

require "fileutils"

require_relative "ledger_commands"

# A piece back with its gates and report, and a verified one whose gates
# stay unsaid, for test/browser/gates.cjs: P1 back, rubocop passed, unit
# failed (2 failures in piece_test.rb), browser running, lint queued,
# its report DONE_WITH_CONCERNS; P2 verified, its gate passed. Made by
# bin/ledger's words in the caller's journal, in one transaction.
module GatesFixture
    GOAL = ["--goal", "a helper hands its work back", "--title",
            "Gates and report", "--short", "gates", "--date",
            "2026-11-22"].freeze
    PIECE = ["--route", "opus, effort: high", "--no-picture",
             "internal"].freeze
    GATES = ["rubocop: passed", "unit: failed (2 failures in piece_test.rb)",
             "browser: running", "lint: queued"].freeze
    REPORT = "DONE_WITH_CONCERNS\nThe runner moved under lib.\n" \
             "- two unit failures remain\n"
    SESSION = ["--session", "gates-fixture"].freeze

    def self.build(journal, address)
        run = lambda do |word, *args|
            LedgerCommands.run(journal, word, address, *args)
        end
        journal.transaction do
            run.call("new", *GOAL)
            back(run, report(address))
            verified(run)
        end
    end

    def self.back(run, report)
        run.call("piece", "new", "--title", "Port the gate runner", *PIECE)
        run.call("piece", "P1", "--status", "out", *SESSION)
        GATES.each { run.call("piece", "P1", "--gate", it) }
        run.call("piece", "P1", "--status", "back", "--handback",
                 "--report", report)
    end

    def self.verified(run)
        run.call("piece", "new", "--title", "Move the fixtures", *PIECE)
        run.call("piece", "P2", "--gate", "unit: passed")
        run.call("piece", "P2", "--status", "verified", "--verified-by", "me",
                 "--evidence", "suite green")
    end

    def self.report(address)
        file = File.join(File.dirname(address), "report.txt")
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, REPORT)
        file
    end
end
