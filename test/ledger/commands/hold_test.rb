# frozen_string_literal: true

require "json"

require_relative "helper"

# `piece P<n> --hold WHY`: stored on a planned piece, shown on its line
# and in the status line instead of `ready, unsent`, cleared by '', by
# any other status, and by itself once the piece it names has settled.
class HoldTest < CommandCase
    ROUTE = ["--route", "sonnet, effort: low"].freeze
    DONE = ["--status", "verified", "--verified-by", "me", "--evidence",
            "ran it"].freeze

    def setup
        super
        ok("piece", BETA, "new", "--title", "Wait for it", *ROUTE)
        ok("piece", BETA, "new", "--title", "The other one", *ROUTE)
    end

    def piece(target, *) = ok("piece", BETA, target, *)

    def status_line = ok("status", BETA)

    def stored = db[:pieces].where(n: 1).get(:hold)

    # Both pieces planned three hours before the clock, so the limit has
    # passed for any that is not held.
    def age_everything
        at = Ledger::Write.now - (3 * 3_600_000)
        db[:events].update(at:)
    end

    def test_a_hold_is_stored_and_shown_on_the_line
        out = piece("P1", "--hold", "waits for the user")

        assert_includes out, "— held: waits for the user"
        assert_equal "waits for the user", stored
    end

    def test_the_status_line_lists_it_as_held_not_unsent
        piece("P1", "--hold", "waits for the user")
        age_everything
        line = status_line

        assert_includes line, " · ready, unsent: P2 (3 h)"
        assert_includes line, " · held: P1 (waits for the user)"
        refute_includes line, "unsent: P1"
    end

    def test_json_carries_the_hold
        piece("P1", "--hold", "waits for the user")
        pieces = JSON.parse(ok("show", "--json", BETA)).fetch("pieces")

        held = pieces.map { it["hold"] }

        assert_equal ["waits for the user", nil], held
    end

    def test_an_empty_reason_clears_it
        piece("P1", "--hold", "waits for the user")

        refute_includes piece("P1", "--hold", ""), "held"
        assert_nil stored
    end

    def test_going_out_clears_it
        piece("P1", "--hold", "waits for the user")
        piece("P1", "--status", "out", "--session", "s1")

        assert_nil stored
        refute_includes status_line, "held:"
    end

    def test_a_status_back_to_planned_keeps_it
        piece("P1", "--hold", "waits for the user")
        piece("P1", "--plan", "sort by name")

        assert_equal "waits for the user", stored
    end

    def test_a_hold_on_a_piece_that_is_not_planned_is_refused
        piece("P1", "--status", "blocked")

        assert_refused("piece", BETA, "P1", "--hold", "later",
                       "--hold holds a planned piece")
    end

    def test_a_hold_naming_a_piece_is_released_when_it_is_verified
        piece("P1", "--hold", "waits for P2")
        age_everything
        assert_includes status_line, "held: P1 (waits for P2)"

        piece("P2", *DONE)
        age_everything
        line = status_line

        refute_includes line, "held:"
        assert_includes line, "ready, unsent: P1"
        assert_equal "waits for P2", stored
    end

    def test_a_hold_naming_a_piece_stays_while_it_is_out
        piece("P1", "--hold", "waits for P2")
        piece("P2", "--status", "out", "--session", "s1")

        assert_includes status_line, "held: P1 (waits for P2)"
        assert_includes piece("P1", "--plan", "x"), "— held: waits for P2"
    end

    def test_an_obsolete_piece_releases_the_hold
        piece("P1", "--hold", "waits for P2")
        piece("P2", "--status", "obsolete", "--obsoleted-by", "P1")

        refute_includes status_line, "held:"
    end

    def test_a_hold_naming_a_piece_the_ledger_lacks_is_refused
        assert_refused("piece", BETA, "P1", "--hold", "waits for P99",
                       "P99 is no piece of this ledger")
        assert_nil stored
    end

    def test_a_hold_naming_no_piece_stays
        piece("P1", "--hold", "the user decides")

        assert_includes status_line, "held: P1 (the user decides)"
    end

    def test_a_dropped_piece_releases_the_hold
        piece("P1", "--hold", "waits for P2")
        piece("P2", "--status", "dropped")

        refute_includes status_line, "held:"
    end
end
