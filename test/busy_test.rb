# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# Another writer holds the journal: a send waits Accounts::BUSY_MS for
# it, then is answered 503, and nothing is filed.
class BusyTest < ViewerTest
    include LedgerFixture
    include Sends

    def test_a_send_waits_the_busy_time_then_is_answered_unavailable
        sign_in
        mine = token
        waited = with_journal_held do
            elapsed { say([%w[ref], %w[text x]], token: mine) }
        end

        assert_equal 503, last_response.status
        assert_includes last_response.body, "The journal is busy"
        assert_operator waited, :>=, LedgerViewer::Accounts::BUSY_MS / 1000.0
        assert_operator waited, :<, 5
        assert_empty entries
    end

    def test_the_same_send_is_filed_once_the_journal_is_free
        sign_in
        mine = token
        with_journal_held { say([%w[ref], %w[text x]], token: mine) }
        say([%w[ref], %w[text x]], token: mine)

        assert_equal 303, last_response.status
        assert_equal(["x"], entries.map { it["text"] })
    end

    private

    # The block's value, while a connection of its own holds the
    # journal's write lock.
    def with_journal_held
        other = SQLite3::Database.new(@journal.path)
        other.execute("BEGIN IMMEDIATE")
        yield
    ensure
        other&.rollback
        other&.close
    end

    def elapsed
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end
end
