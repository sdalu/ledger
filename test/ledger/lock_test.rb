# frozen_string_literal: true

require_relative "helper"

# Two writers on one journal: BEGIN IMMEDIATE serializes them, and a
# writer still waiting after the busy timeout is refused. The holder is
# another process, as another session or the viewer would be.
class LockTest < JournalTest
    def teardown
        Process.wait(@holder) if @holder
        super
    end

    # A process holding the write lock for `seconds`, then writing one
    # noticed line; it answers on the pipe once the lock is its own.
    def hold_lock(seconds)
        reader, writer = IO.pipe
        db.disconnect
        @holder = fork { hold(seconds, writer) }
        writer.close
        reader.gets
        reader.close
    end

    def hold(seconds, writer)
        journal = Ledger::Journal.open
        journal.transaction do
            journal.db[:noticed].insert(ledger_id: @ledger[:id], line: "held")
            writer.puts "locked"
            sleep seconds
        end
        Process.exit!(0)
    end

    def lines = db[:noticed].order(:id).select_map(:line)

    def test_a_second_writer_waits_then_writes_after_the_first
        hold_lock(0.5)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        write { it.insert(:noticed, line: "waited") }
        waited = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        assert_operator waited, :>=, 0.3
        assert_equal %w[held waited], lines
    end

    def test_a_writer_still_waiting_after_the_timeout_is_refused
        hold_lock(1.5)
        hurried = Ledger::Journal.open(busy_ms: 200)
        error = refusal(hurried)

        assert_equal "journal is locked by another writer", error.message
        reap

        assert_equal %w[held], lines
    ensure
        hurried&.close
    end

    private

    # A write through `journal`, expected to be refused.
    def refusal(journal)
        assert_raises(Ledger::Locked) do
            Ledger::Write.run(journal, ADDRESS, "noticed", []) do |change|
                change.insert(:noticed, line: "refused")
            end
        end
    end

    # The holder done: its line is in, the refused one is not.
    def reap
        Process.wait(@holder)
        @holder = nil
    end
end
