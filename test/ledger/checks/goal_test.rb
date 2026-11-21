# frozen_string_literal: true

require_relative "runner_test"

# goal-titled, goal-revision, and the Goal part of case-rated.
class GoalChecksTest < CheckCase
    def test_a_title_that_is_not_one_fails_goal_titled
        goal(title: "O13 D1")

        assert_fails "goal-titled",
                     "#{Ledger::Checks::Goal::TITLED}Goal G2 (2026-11-20, " \
                     "verbatim): #{Ledger::Text::Title::MOSTLY_IDS}"
    end

    def test_a_goal_without_title_passes_goal_titled
        goal(title: nil)

        assert_passes "goal-titled"
    end

    def test_a_revision_of_three_words_fails_goal_revision
        goal(stamp: "2026-11-21, revised", revised: true, quote: "do it now")

        assert_fails "goal-revision", "#{Ledger::Checks::Goal::GO_AHEAD}: " \
                                      "Goal G2 (2026-11-21, revised):"
    end

    def test_a_revision_of_four_words_passes
        goal(revised: true, quote: "do it right now")

        assert_passes "goal-revision"
    end

    def test_the_latest_goal_without_title_and_short_fails_case_rated
        goal(title: nil, short: nil)

        assert_fails "case-rated", "the latest Goal block without " \
                                   "`Title:`; the latest Goal block without " \
                                   "`In short:`"
    end
end
