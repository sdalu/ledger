# frozen_string_literal: true

require_relative "helper"

# `inbox`: the entries nobody has taken, printed as `ledger inbox`
# prints them; `--wait` and `--follow` on a real clock.
class InboxCommandTest < CommandCase
    def setup
        super
        @poll = Ledger::Inbox.poll
        Ledger::Inbox.poll = 0.05
    end

    def teardown
        Ledger::Inbox.poll = @poll
        super
    end

    def send_entry(text = "hello", **fields)
        Ledger::Inbox.append(@journal, BETA, [{ "text" => text, **fields }],
                             actor: "cli", now: Time.new(2026, 11, 21, 8, 0, 0))
    end

    # An entry sent from another connection after SECONDS.
    def send_later(seconds)
        Thread.new do
            sleep(seconds)
            journal = Ledger::Journal.open
            Ledger::Inbox.append(journal, BETA, [{ "text" => "late" }],
                                 actor: "viewer:anna")
        ensure
            journal.close
        end
    end

    def timed
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        [result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - start]
    end

    def test_an_empty_inbox_says_so
        assert_equal "inbox: nothing pending\n", ok("inbox", BETA)
    end

    def test_pending_entries_print_in_order
        send_entry("warm", ref: "O1")
        send_entry("see this", ref: "P1")
        ok("take", BETA, "N1")
        send_entry("note")
        assert_equal "N2 (2026-11-21 08:00:00, comment on piece P1):\n    " \
                     "see this\n" \
                     "N3 (2026-11-21 08:00:00, note):\n    note\n",
                     ok("inbox", BETA)
    end

    def test_a_malformed_line_is_shown_whole
        Ledger::Write.run(@journal, BETA, "import", []) do |change|
            change.insert(:inbox_entries, n: 1, at: "", payload: "{broken",
                                          malformed: true)
        end
        assert_equal "N1 (?, malformed line):\n    {broken\n",
                     ok("inbox", BETA)
    end

    def test_an_unknown_address_is_refused
        assert_refused("inbox", "/work/none/LEDGER.md",
                       "no live ledger at /work/none/LEDGER.md")
    end

    def test_wait_returns_at_once_when_an_entry_is_pending
        send_entry
        out, seconds = timed { ok("inbox", BETA, "--wait") }
        assert_includes out, "N1 (2026-11-21 08:00:00, note)"
        assert_operator seconds, :<, 0.5
    end

    def test_wait_wakes_on_an_entry_sent_meanwhile
        thread = send_later(0.3)
        (out, seconds) = timed { ok("inbox", BETA, "--wait", "--timeout", "5") }
        thread.join
        assert_includes out, "late"
        assert_in_delta 0.3, seconds, 0.25
    end

    def test_wait_times_out_with_one
        (result, seconds) = timed do
            cli("inbox", BETA, "--wait", "--timeout",
                "0.3")
        end
        assert_equal [1, "", ""], result
        assert_operator seconds, :>=, 0.3
        assert_operator seconds, :<, 1.5
    end

    def test_follow_prints_a_burst_together_after_the_lull
        thread = send_later(0.2)
        (result, seconds) = timed do
            cli("inbox", BETA, "--follow", "--quiet", "0.3", "--timeout", "1.5")
        end
        thread.join
        assert_equal 1, result[0]
        assert_includes result[1], "late"
        assert_operator seconds, :>=, 1.5
    end

    def test_follow_with_a_bad_number_is_a_usage_error
        assert_refused("inbox", BETA, "--follow", "--quiet", "soon",
                       "invalid argument")
    end

    def test_follow_restores_the_signal_handlers
        before = %w[TERM INT HUP].map { Signal.trap(it, "DEFAULT") }
        cli("inbox", BETA, "--follow", "--timeout", "0.1")
        after = %w[TERM INT HUP].map { Signal.trap(it, "DEFAULT") }
        assert_equal ["DEFAULT"] * 3, after
        %w[TERM INT HUP].zip(before) { |sig, old| Signal.trap(sig, old) }
    end
end
