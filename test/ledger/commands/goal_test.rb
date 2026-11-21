# frozen_string_literal: true

require_relative "helper"

# `goal`: a revised Goal block quoting the user's new words.
class GoalTest < CommandCase
    REVISION = ["--quote", "do the other thing instead", "--title",
                "The other thing", "--short", "instead", "--date",
                "2026-11-21"].freeze

    def test_a_revised_block_is_added_and_printed_before_the_status_line
        out = ok("goal", BETA, *REVISION)
        assert_equal ["Goal (2026-11-21, revised, verbatim):",
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
end
