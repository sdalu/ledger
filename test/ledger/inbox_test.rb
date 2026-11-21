# frozen_string_literal: true

require_relative "commands/helper"

# `Ledger::Inbox.append`: the viewer's way in, numbered in the write
# transaction, one `inbox` event per call.
class InboxApiTest < CommandCase
    def append(*entries, **)
        Ledger::Inbox.append(@journal, BETA, entries,
                             actor: "viewer:anna", **)
    end

    def test_entries_are_numbered_in_one_event
        ids = append({ "ref" => "O1", "text" => "warm" }, { "text" => "hi" })
        assert_equal %w[N1 N2], ids
        events = db[:events].where(command: "inbox")
        assert_equal [["viewer:anna", "N1, N2"]],
                     events.select_map(%i[actor summary])
        assert_equal [1, 2], db[:inbox_entries].order(:id).select_map(:n)
    end

    def test_the_payload_is_the_viewers_line
        append({ ref: "O1", word: "x", text: "warm\nsecond" },
               now: Time.new(2026, 11, 21, 9, 5, 7))
        row = db[:inbox_entries].first
        assert_equal ["2026-11-21 09:05:07", "O1", false],
                     row.values_at(:at, :ref, :malformed)
        assert_equal({ "id" => "N1", "at" => "2026-11-21 09:05:07",
                       "ref" => "O1", "word" => "x",
                       "text" => "warm\nsecond" },
                     JSON.parse(row[:payload]))
        assert_equal %w[id at ref word text], JSON.parse(row[:payload]).keys
    end

    def test_a_number_is_never_given_twice
        append({ "text" => "a" })
        ok("take", BETA, "N1")
        assert_equal ["N2"], append({ "text" => "b" })
    end

    # Five entries sent from a connection of its own.
    def sender(name)
        Thread.new do
            journal = Ledger::Journal.open
            5.times do |i|
                entry = { "text" => "#{name}#{i}" }
                Ledger::Inbox.append(journal, BETA, [entry],
                                     actor: "viewer:#{name}")
            end
        ensure
            journal.close
        end
    end

    def test_writers_at_once_get_distinct_numbers
        %w[a b].map { sender(it) }.each(&:join)
        assert_equal (1..10).to_a, db[:inbox_entries].order(:n).select_map(:n)
    end

    # An entry refused, after a good one, with nothing written.
    def refused(entry, message)
        before = state
        error = assert_raises(Ledger::Refused) do
            append({ "text" => "fine" }, entry)
        end
        assert_includes error.message, message
        assert_equal before, state
    end

    def test_an_entry_is_checked_before_any_is_written
        refused({ "text" => 4 }, "needs its text")
        refused({ "ref" => "O1" }, "needs its text")
        refused({ "ref" => "F1", "text" => "x" }, "ref is O<n>")
        refused({ "id" => "N9", "text" => "x" }, "id is the journal's")
        refused({ "at" => "x", "text" => "x" }, "at is the journal's")
    end

    def test_nothing_to_send_and_no_such_ledger
        assert_raises(Ledger::Refused) { append }
        assert_raises(Ledger::Unknown) do
            Ledger::Inbox.append(@journal, "/work/none/LEDGER.md",
                                 [{ "text" => "x" }], actor: "cli")
        end
    end

    def test_show_prints_an_entry_and_a_malformed_line
        append({ "ref" => "O1", "word" => nil, "text" => "warm" },
               now: Time.new(2026, 11, 21, 9, 5, 7))
        assert_equal "N1 (2026-11-21 09:05:07, answer to O1):\n    warm",
                     Ledger::Inbox.show(db[:inbox_entries].first)
        row = { n: 7, payload: "not json\nsecond", malformed: true }
        assert_equal "N7 (?, malformed line):\n    not json\n    second",
                     Ledger::Inbox.show(row)
    end

    def test_show_names_a_picture_asked_by_its_kind
        append({ "ref" => "O3", "picture" => "svg", "text" => "the tree" },
               now: Time.new(2026, 11, 21, 9, 6, 0))
        assert_equal "N1 (2026-11-21 09:06:00, picture asked for O3 " \
                     "(svg)):\n    the tree",
                     Ledger::Inbox.show(db[:inbox_entries].first)
    end
end

# `Ledger::Inbox::Watch` on a fake clock: the polling, the burst held
# until a lull, the entry taken while held, the stop.
class InboxWatchTest < CommandCase
    # What the watch printed, each write with the time it was made.
    class Recorder
        attr_reader :writes

        def initialize(clock)
            @clock = clock
            @writes = []
        end

        def puts(text) = @writes << [@clock.call, text]
    end

    def setup
        super
        @time = 0.0
        @actions = {}
        @out = Recorder.new(-> { @time })
    end

    # A watch whose clock only moves when it sleeps; ACTIONS maps a
    # second to what happens then.
    def watch(**)
        sleeper = lambda do |seconds|
            @time += seconds
            @actions.delete(@time.round)&.call
        end
        Ledger::Inbox::Watch.new(@journal, @beta, @out, poll: 1, sleeper:,
                                                        clock: -> { @time },
                                                        **)
    end

    def send_at(second, text)
        @actions[second] = lambda do
            Ledger::Inbox.append(@journal, BETA, [{ "text" => text }],
                                 actor: "cli")
        end
    end

    def texts = @out.writes.map(&:last)

    def test_wait_prints_what_is_already_pending_at_once
        Ledger::Inbox.append(@journal, BETA, [{ "text" => "now" }],
                             actor: "cli")
        assert_equal 0, watch.call
        assert_equal [[0.0, texts.first]], @out.writes
        assert_includes texts.first, "now"
    end

    def test_wait_ends_with_one_at_its_timeout
        assert_equal 1, watch(timeout: 3).call
        assert_equal 3.0, @time
        assert_empty @out.writes
    end

    def test_wait_wakes_on_the_entry_that_arrives
        send_at(2, "late")
        assert_equal 0, watch(timeout: 9).call
        assert_equal [2.0], @out.writes.map(&:first)
        assert_includes texts.first, "late"
    end

    def test_an_entry_already_taken_does_not_wake_a_wait
        Ledger::Inbox.append(@journal, BETA, [{ "text" => "a" }],
                             actor: "cli")
        ok("take", BETA, "N1")
        assert_equal 1, watch(timeout: 2).call
        assert_empty @out.writes
    end

    def test_follow_holds_a_burst_until_a_lull
        send_at(1, "one")
        send_at(2, "two")
        assert_equal 1, watch(follow: true, quiet: 3, timeout: 9).call
        assert_equal [5.0], @out.writes.map(&:first)
        assert_match(/one.*N2 .*two/m, texts.first)
    end

    def test_follow_with_no_quiet_prints_each_at_once
        send_at(1, "one")
        send_at(3, "two")
        watch(follow: true, quiet: 0, timeout: 4).call
        assert_equal [1.0, 3.0], @out.writes.map(&:first)
    end

    def test_an_entry_taken_while_held_is_not_printed
        send_at(1, "one")
        @actions[2] = -> { ok("take", BETA, "N1") }
        watch(follow: true, quiet: 5, timeout: 9).call
        assert_empty @out.writes
    end

    def test_an_entry_is_printed_once_whatever_else_happens
        send_at(1, "one")
        @actions[2] = -> { ok("fact", BETA, "a — b") }
        watch(follow: true, quiet: 0, timeout: 4).call
        assert_equal [1.0], @out.writes.map(&:first)
    end

    def test_a_stop_prints_the_burst_still_held
        send_at(1, "one")
        @actions[3] = -> { raise SystemExit }
        assert_raises(SystemExit) { watch(follow: true, quiet: 60).call }
        assert_equal 1, @out.writes.size
        assert_includes texts.first, "one"
    end
end
