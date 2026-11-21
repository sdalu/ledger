# frozen_string_literal: true

require_relative "runner_test"

# The --final rules, which a plain check does not run.
class FinalChecksTest < CheckCase
    def test_unfinished_pieces_fail_final_pieces
        piece
        piece(status: "back")
        piece(status: "blocked")

        assert_fails "final-pieces", "still open: P1 [planned], P2 [back]",
                     final: true
        assert_nil report("final-pieces")
    end

    def test_an_owed_word_fails_final_awaits
        id = piece(status: "verified", evidence: "ok", problem: "p",
                   risk: "1/10 — x", risk_rating: 1)
        awaits(id, "commit", "deploy")

        assert_fails "final-awaits",
                     "the user's word still owed: P1 (commit, deploy)",
                     final: true
    end

    def test_criteria_unmarked_or_without_reason_fail_final_criteria
        criterion
        criterion(mark: "x")
        criterion(mark: "-")

        assert_fails "final-criteria", "D2 unmarked; D3 met without " \
                                       "evidence; D4 not met without why:",
                     final: true
    end

    def test_no_criterion_fails_final_criteria
        db[:criteria].delete

        assert_fails "final-criteria", "", final: true
    end
end
