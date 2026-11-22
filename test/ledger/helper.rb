# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "fileutils"
require "minitest/autorun"
require "tmpdir"

require "ledger"
require "ledger/pictures"

# A journal in a temporary directory, named through LEDGER_JOURNAL as a
# command would find it, with one live ledger; nothing under
# ~/.local/state is ever reached.
class JournalTest < Minitest::Test
    ADDRESS = "/work/alpha/LEDGER.md"

    # The variables as the suite set them: a teardown that deleted them
    # would leave the tests after it reading the running session's
    # transcript.
    KEPT = %w[LEDGER_JOURNAL CLAUDE_CONFIG_DIR].freeze

    def setup
        @suite_env = ENV.to_h.slice(*KEPT)
        @dir = Dir.mktmpdir("ledger-journal-test")
        ENV["LEDGER_JOURNAL"] = File.join(@dir, "state", "journal.db")
        # No real session's transcript is read: a test writes its own.
        ENV["CLAUDE_CONFIG_DIR"] = File.join(@dir, "claude")
        @journal = Ledger::Journal.open
        @ledger = @journal.create_ledger(ADDRESS, project: "alpha")
    end

    def teardown
        @journal.close
        KEPT.each { ENV[it] = @suite_env[it] }
        FileUtils.rm_rf(@dir)
    end

    def db = @journal.db

    # {name => bytes} of the pictures (each path), read through the
    # blob each row points to.
    def picture_bytes
        db[:pictures].join(:picture_blobs, sha256: :sha256)
                     .to_hash(:name, :bytes).transform_values { it.to_s.b }
    end

    # One write on the fixture ledger, as a command would run it.
    def write(command = "piece", argv = [], **, &)
        Ledger::Write.run(@journal, ADDRESS, command, argv, **, &)
    end

    # A planned piece with a route, the smallest row the schema takes;
    # verified by me when verified, claimed by s1 when out.
    def piece(change, **columns)
        n = change.next_id("P")
        status = columns[:status]
        row = { n:, status: "planned", model: "sonnet", effort: "low",
                dash: false, title: "Piece #{n}",
                verified_by: ("me" if status == "verified"),
                claimed_by: ("s1" if status == "out") }
        change.insert(:pieces, **row, **columns)
    end

    def events = db[:events].order(:id).all
    def event_rows = db[:event_rows].order(:event_id, :rowid).all
end
