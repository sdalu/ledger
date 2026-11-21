# frozen_string_literal: true

require_relative "helper"

# `take`: entries marked taken in one `take` event; one taken before, or
# unknown, is refused.
class TakeTest < CommandCase
    def setup
        super
        entries = [{ "text" => "one" }, { "text" => "two" },
                   { "text" => "three" }]
        Ledger::Inbox.append(@journal, BETA, entries, actor: "viewer:anna")
    end

    def test_entries_are_taken_in_one_event
        out = ok("take", BETA, "N1", "N3")
        assert_equal "taken: N1, N3; pending: N2\n", out
        event = db[:events].order(:id).last
        assert_equal ["take", "taken: N1, N3"],
                     event.values_at(:command, :summary)
        assert_equal [event[:id], nil, event[:id]],
                     db[:inbox_entries].order(:n).select_map(:taken_id)
    end

    def test_a_repeated_id_is_taken_once
        assert_equal "taken: N2; pending: N1, N3\n",
                     ok("take", BETA, "N2", "N2")
    end

    def test_when_nothing_is_left_pending_says_none
        assert_equal "taken: N1, N2, N3; pending: none\n",
                     ok("take", BETA, "N1", "N2", "N3")
    end

    def test_an_unknown_entry_is_refused_and_nothing_is_taken
        assert_refused("take", BETA, "N1", "N9", "take: no inbox entry N9")
        assert_equal [nil] * 3, db[:inbox_entries].select_map(:taken_id)
        assert_refused("take", BETA, "O1", "no inbox entry O1")
    end

    def test_an_entry_taken_before_is_refused
        ok("take", BETA, "N1")
        assert_refused("take", BETA, "N2", "N1",
                       "N1 was already taken at ")
        assert_refused("take", BETA, "N1",
                       "another session filed it")
    end

    def test_an_entry_of_another_ledger_is_unknown
        @journal.create_ledger("/work/other/LEDGER.md", project: "o")
        Ledger::Inbox.append(@journal, "/work/other/LEDGER.md",
                             [{ "text" => "x" }] * 4, actor: "cli")
        assert_refused("take", BETA, "N4", "no inbox entry N4")
    end

    def test_a_path_and_an_id_are_needed
        assert_refused("take", BETA, "usage: ledger take PATH ID...")
        assert_refused("take", "usage: ledger take PATH ID...")
    end
end
