# frozen_string_literal: true

require "json"

require_relative "helper"

# `goal`: a revised Goal block quoting the user's new words.
class GoalTest < CommandCase
    REVISION = ["--quote", "do the other thing instead", "--title",
                "The other thing", "--short", "instead", "--date",
                "2026-11-21"].freeze

    def test_a_revised_block_is_added_and_printed_before_the_status_line
        out = ok("goal", BETA, *REVISION)
        assert_equal ["Goal G2 (2026-11-21, revised, verbatim):",
                      "Title: The other thing", "In short: instead",
                      "> do the other thing instead"],
                     out.lines(chomp: true)[0..3]
        assert_match(/\AStatus — /, out.lines.last)
        assert_equal 2, snapshot.goals.size
        assert snapshot.goals.last[:revised]
    end

    def test_a_dry_run_prints_the_diff_and_writes_nothing
        before = state
        out = ok("goal", BETA, *REVISION, "--dry-run")
        assert_includes out, "+++ #{BETA} (after)"
        assert_includes out, "dry run: nothing written"
        assert_equal before, state
    end

    def test_a_bad_title_is_refused
        assert_refused("goal", BETA, "--quote", "do the other thing instead",
                       "--title", "Why: no", "--short", "s",
                       "goal: the title holds `: `")
    end

    def test_a_missing_option_is_a_usage_error
        assert_refused("goal", BETA, "--title", "Some title", "--short", "s",
                       "goal: --quote is required")
    end

    def test_an_empty_short_is_refused
        assert_refused("goal", BETA, "--quote", "do the other thing instead",
                       "--title", "Some title", "--short", "",
                       "--short is empty")
    end

    def test_a_goal_block_is_needed_to_edit_the_title
        db[:goals].delete
        assert_refused("edit", BETA, "goal", "--text", "A title",
                       "no Goal block to edit")
    end

    def test_a_go_ahead_is_refused
        assert_refused("goal", BETA, "--quote", "do it", "--title",
                       "Some title", "--short", "s", "goal: a go-ahead")
    end

    def test_each_block_takes_the_next_g_number
        ok("goal", BETA, *REVISION)
        ok("goal", BETA, *REVISION)
        assert_equal([1, 2, 3], snapshot.goals.map { it[:n] })
    end

    def test_a_g_number_undone_is_never_given_again
        ok("goal", BETA, *REVISION)
        ok("undo", BETA)
        ok("goal", BETA, *REVISION)
        assert_equal([1, 3], snapshot.goals.map { it[:n] })
    end
end

# `goal PATH G<n> --done EVIDENCE | --undone`: a Goal block marked done,
# or active again, through the write path.
class GoalMarkTest < CommandCase
    def test_done_marks_the_block_and_prints_it
        out = ok("goal", BETA, "G1", "--done", "shipped in v2")
        assert_equal ["Goal G1 (2026-11-20, verbatim):",
                      "Title: Build the thing", "In short: build it",
                      "Done: shipped in v2", "> build the thing now"],
                     out.lines(chomp: true)[0..4]
        assert_match(/\AStatus — /, out.lines.last)
    end

    def test_done_stores_the_evidence_and_the_events_time
        ok("goal", BETA, "G1", "--done", "shipped in v2")
        row = snapshot.goals.first
        assert_equal "shipped in v2", row[:done_evidence]
        assert_equal db[:events].order(:id).last[:at], row[:done_at]
    end

    def test_undone_clears_the_time_and_the_evidence
        ok("goal", BETA, "G1", "--done", "shipped")
        ok("goal", BETA, "G1", "--undone")
        assert_equal [nil, nil],
                     snapshot.goals.first.values_at(:done_at, :done_evidence)
        refute_includes markdown, "Done:"
    end

    def test_undo_takes_the_mark_back
        ok("goal", BETA, "G1", "--done", "shipped")
        ok("undo", BETA)
        assert_equal [nil, nil],
                     snapshot.goals.first.values_at(:done_at, :done_evidence)
    end

    def test_restore_takes_the_mark_back
        before = db[:events].order(:id).last[:id]
        ok("goal", BETA, "G1", "--done", "shipped")
        ok("goal", BETA, *GoalTest::REVISION)
        ok("restore", BETA, "--to", "E#{before}")
        assert_equal([[1, nil]],
                     snapshot.goals.map { it.values_at(:n, :done_at) })
    end

    def test_a_dry_run_writes_nothing
        before = state
        out = ok("goal", BETA, "G1", "--done", "x", "--dry-run")
        assert_includes out, "+Done: x"
        assert_equal before, state
    end

    def test_an_unknown_goal_is_refused
        assert_refused("goal", BETA, "G2", "--done", "x",
                       "G2 is not a Goal block of this ledger")
    end

    def test_a_target_that_is_not_g_n_is_refused
        assert_refused("goal", BETA, "D1", "--done", "x",
                       "the target is G<n>")
    end

    def test_done_with_empty_evidence_is_refused
        assert_refused("goal", BETA, "G1", "--done", "  ",
                       "--done takes the evidence; it is empty")
    end

    def test_done_on_a_done_block_is_refused
        ok("goal", BETA, "G1", "--done", "shipped")
        assert_refused("goal", BETA, "G1", "--done", "again",
                       "G1 is done already")
    end

    def test_undone_on_an_active_block_is_refused
        assert_refused("goal", BETA, "G1", "--undone", "G1 is not done")
    end

    def test_done_with_quote_is_refused
        assert_refused("goal", BETA, "G1", "--done", "x", "--quote",
                       "do the other thing instead", "go without --quote")
    end

    def test_done_and_undone_together_are_refused
        assert_refused("goal", BETA, "G1", "--done", "x", "--undone",
                       "give one of --done EVIDENCE, --undone")
    end

    def test_done_without_a_goal_id_is_refused
        assert_refused("goal", BETA, "--done", "x",
                       "--done and --undone name a goal")
    end

    def test_show_prints_a_goals_fields
        ok("goal", BETA, "G1", "--done", "shipped")
        out = ok("show", BETA, "G1")
        assert_includes out.lines(chomp: true), "id: G1"
        assert_includes out.lines(chomp: true), "done: true"
        assert_includes out.lines(chomp: true), "done_evidence: shipped"
        assert_includes out.lines(chomp: true), "title: Build the thing"
    end

    def test_the_json_carries_the_id_and_the_mark
        ok("goal", BETA, "G1", "--done", "shipped")
        goal = JSON.parse(ok("show", BETA, "--json"))["goals"].first
        assert_equal ["G1", true, "shipped"],
                     goal.values_at("id", "done", "done_evidence")
    end
end
