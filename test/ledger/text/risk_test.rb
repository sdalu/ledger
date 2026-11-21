# frozen_string_literal: true

require "minitest/autorun"

require "ledger/text/risk"

# Cases of risk_rating and case_problem, from
# check-ledger-write.sh (unrated-risk, risk-over-ten, no-problem,
# no-risk refusals).
class RiskTest < Minitest::Test
    Risk = Ledger::Text::Risk

    def test_rating_splits_number_and_what
        assert_equal [7, "the cache goes stale"],
                     Risk.rating("7/10 — the cache goes stale")
        assert_equal [3, "r"], Risk.rating("3/10 — r")
        assert_equal [0, "nothing to lose"],
                     Risk.rating("  0/10 — nothing to lose ")
    end

    def test_rating_bare
        assert_equal [5, ""], Risk.rating("5/10")
    end

    def test_unrated_keeps_its_text
        assert_equal [nil, "a redo"], Risk.rating("a redo")
        assert_equal [nil, "about 5/10 — x"], Risk.rating("about 5/10 — x")
        assert_equal [nil, "5/100 — x"], Risk.rating("5/100 — x")
    end

    def test_rating_over_ten_is_read_then_refused
        assert_equal [12, "a redo"], Risk.rating("12/10 — a redo")
        assert_equal "a risk rated 0 to 10, not 12",
                     Risk.case_problem("p", "12/10 — a redo")
    end

    def test_case_complete
        assert_nil Risk.case_problem("p", "5/10 — r")
        assert_nil Risk.case_problem("p", "10/10 — all lost")
    end

    def test_no_problem
        assert_equal "--problem: what is wrong or missing, and where",
                     Risk.case_problem(" ", "5/10 — r")
    end

    def test_unrated_or_missing_risk
        want = '--risk "N/10 — what goes wrong", N from 0 to 10'
        assert_equal want, Risk.case_problem("p", "a redo")
        assert_equal want, Risk.case_problem("p", "")
        assert_equal want, Risk.case_problem("p", "5/10")
    end
end
