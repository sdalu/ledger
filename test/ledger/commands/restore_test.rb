# frozen_string_literal: true

require_relative "helper"

# What the `restore` tests share: three facts, the first one the mark.
class RestoreCase < CommandCase
    def fact(text) = ok("fact", BETA, text).lines.first.chomp
    def last_event = db[:events].order(:id).last

    def three_facts
        fact("a — one")
        @mark = last_event[:id]
        fact("b — two")
        fact("c — three")
    end
end

# `restore --to E<n>`: every item-changing event after E<n> reverted,
# newest first, in one event.
class RestoreTest < RestoreCase
    def test_every_later_event_is_reverted_in_one_event
        three_facts
        out = ok("restore", BETA, "--to", "E#{@mark}")
        assert_equal "restored: #{BETA} is back as at E#{@mark}",
                     out.lines.first.chomp
        assert_match(/\AStatus \(Build the thing\) — /, out.lines.last)
        assert_equal [1], db[:facts].select_map(:n)
    end

    def test_the_restore_is_one_event_naming_its_target
        three_facts
        count = db[:events].count
        ok("restore", BETA, "--to", "E#{@mark}")
        assert_equal count + 1, db[:events].count
        assert_equal ["restore", @mark],
                     last_event.values_at(:command, :undoes)
    end

    def test_the_restore_event_holds_each_row_it_changed
        three_facts
        ok("restore", BETA, "--to", "E#{@mark}")
        assert_equal 2, db[:event_rows].where(event_id: last_event[:id]).count
    end

    def test_a_restore_walks_back_over_an_undo
        three_facts
        ok("undo", BETA)
        ok("restore", BETA, "--to", "E#{@mark}")
        assert_equal 1, db[:facts].count
    end

    def test_a_restore_can_be_undone
        three_facts
        ok("restore", BETA, "--to", "E#{@mark}")
        ok("undo", BETA)
        assert_equal 3, db[:facts].count
    end

    def test_inbox_and_take_events_stay
        three_facts
        Ledger::Inbox.append(@journal, BETA, [{ "text" => "hi" }],
                             actor: "cli")
        ok("take", BETA, "N1")
        ok("restore", BETA, "--to", "E#{@mark}")
        assert_equal 1, db[:facts].count
        refute_nil db[:inbox_entries].get(:taken_id)
    end
end

# `restore` listing and refusing: each case leaves the ledger as it was.
class RestoreRefusalTest < RestoreCase
    def test_without_to_the_last_ten_events_are_listed
        12.times { |i| fact("f#{i} — p") }
        before = state
        code, out, err = cli("restore", BETA)
        assert_equal 2, code
        assert_includes err, "restore: --to E<n> is required"
        assert_equal 10, out.lines.size
        assert_equal before, state
    end

    def test_a_listed_event_is_its_id_time_actor_and_command
        fact("f — p")
        stamp = /\d{4}-\d\d-\d\d \d\d:\d\d:\d\d/
        listed = cli("restore", BETA)[1].lines
        assert_match(/\AE#{last_event[:id]}  #{stamp}  \S+  fact\n/,
                     listed.first)
        assert_match(/  new\n\z/, listed.last)
    end

    def test_the_event_must_be_this_ledgers
        other = @journal.create_ledger("/work/other/LEDGER.md", project: "o")
        foreign = Ledger::Write.run(@journal, "/work/other/LEDGER.md", "x",
                                    []) { nil }.event
        three_facts
        assert_equal other[:id], foreign[:ledger_id]
        assert_refused("restore", BETA, "--to", "E#{foreign[:id]}",
                       "E#{foreign[:id]} is not this ledger's")
        assert_refused("restore", BETA, "--to", "E9999",
                       "E9999 is not this ledger's")
    end

    def test_to_takes_an_event_id
        three_facts
        assert_refused("restore", BETA, "--to", "12", "--to takes an event id")
        assert_refused("restore", BETA, "--to", "E0", "--to takes an event id")
    end

    def test_nothing_after_the_event_is_refused
        three_facts
        assert_refused("restore", BETA, "--to", "E#{last_event[:id]}",
                       "nothing to restore after")
    end

    def test_a_row_changed_since_is_refused
        three_facts
        db[:facts].where(n: 2).update(text: "by hand")
        assert_refused("restore", BETA, "--to", "E#{@mark}",
                       "facts row 2 changed since")
        assert_equal 3, db[:facts].count
    end

    def test_a_dry_run_writes_nothing
        three_facts
        before = state
        out = ok("restore", BETA, "--to", "E#{@mark}", "--dry-run")
        assert_includes out, "dry run: nothing written"
        assert_equal before, state
    end
end
