# frozen_string_literal: true

require_relative "helper"

# `decide`: a decision, its X id first, its edges written with it.
class DecideTest < CommandCase
    DATE = ["--date", "2026-11-20"].freeze

    def setup
        super
        ok("fact", BETA, "a — b")
        ok("constraint", BETA, "q", "--where", "w")
    end

    def test_a_decision_is_written_with_its_id_first
        out = ok("decide", BETA, "O3: take B", "--by", "user", "--note",
                 "turn 4", *DATE)
        assert_equal ["X1", "- 2026-11-20 — O3: take B — by user (turn 4)"],
                     out.lines(chomp: true)[0..1]
        assert_equal "O3", db[:decisions].get(:subject)
    end

    def test_edges_are_written_with_the_decision
        ok("decide", BETA, "first", "--by", "me", *DATE)
        ok("decide", BETA, "second", "--by", "me", *DATE, "--rests-on",
           "F1,C1", "--replaces", "X1")
        kinds = db[:links].order(:id).select_map(:kind)
        assert_equal %w[rests_on rests_on replaces], kinds
    end

    def test_a_dry_run_writes_nothing
        before = state
        out = ok("decide", BETA, "x", "--by", "me", "--dry-run")
        assert_equal "X1", out.lines.first.chomp
        assert_equal before, state
    end

    def test_by_must_be_user_or_me
        assert_refused("decide", BETA, "x", "--by", "them",
                       "--by is user or me")
        assert_refused("decide", BETA, "x", "--by is user or me")
    end

    def test_an_empty_decision_is_refused
        assert_refused("decide", BETA, " ", "--by", "me",
                       "the decision is empty")
    end

    def test_a_note_with_parentheses_is_not_a_decision_line
        assert_refused("decide", BETA, "x", "--by", "me", "--note", "a (b)",
                       "not a decision line")
    end

    def test_a_target_of_another_kind_is_refused
        assert_refused("decide", BETA, "x", "--by", "me", "--rests-on", "P1",
                       "--rests-on takes F/C ids, not P1")
        assert_refused("decide", BETA, "x", "--by", "me", "--replaces", "F1",
                       "--replaces takes X ids")
        assert_refused("decide", BETA, "x", "--by", "me", "--led-to", "F1",
                       "--led-to takes P/O ids")
    end

    def test_a_target_that_is_not_this_ledgers_is_refused
        assert_refused("decide", BETA, "x", "--by", "me", "--rests-on", "F9",
                       "F9 is not this ledger's")
        assert_refused("decide", BETA, "x", "--by", "me", "--led-to", "O9",
                       "O9 is not this ledger's")
    end
end
