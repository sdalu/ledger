# frozen_string_literal: true

require "minitest/autorun"

require "ledger/text/risk"
require "ledger/text/step_risk"

# The step risk table, read off the word: start 0, commit 1, merge 2,
# push 4, deploy 5, 3 more when irreversible, capped at 10; and the work
# risk's source, the last dispatch's rating before the piece's own.
class StepRiskTest < Minitest::Test
    Step = Ledger::Text::StepRisk

    TABLE = { "start" => [0, 3], "commit" => [1, 4], "merge" => [2, 5],
              "push" => [4, 7], "deploy" => [5, 8] }.freeze

    def test_each_word_weighs_its_step_and_three_more_irreversible
        TABLE.each do |word, (plain, irreversible)|
            assert_equal plain, Step.of(word), word
            assert_equal irreversible, Step.of(word, irreversible: true), word
        end
    end

    def test_other_weighs_nothing
        assert_nil Step.of("other")
        assert_nil Step.max(%w[other])
        assert_nil Step.max([])
    end

    def test_several_words_give_the_highest_not_the_sum
        assert_equal 4, Step.max(%w[commit push])
        assert_equal 8, Step.max(%w[commit merge push deploy],
                                 irreversible: true)
        assert_equal 1, Step.max(%w[commit other])
    end

    def test_the_rating_is_capped_at_ten
        stub_const(:IRREVERSIBLE, 7) do
            assert_equal 10, Step.of("deploy", irreversible: true)
        end
    end

    def test_the_work_risk_is_the_dispatch_rating_before_the_own
        own = [3, "3/10 — own"]

        assert_equal [6, "6/10 — d"],
                     Ledger::Text::Risk.work(own, [6, "6/10 — d"])
        assert_equal own, Ledger::Text::Risk.work(own, [nil, "unrated"])
        assert_equal own, Ledger::Text::Risk.work(own, nil)
    end

    private

    # The table's +3 never reaches the cap; a larger bonus shows it holds.
    def stub_const(name, value)
        old = Step.const_get(name)
        Step.send(:remove_const, name)
        Step.const_set(name, value)
        yield
    ensure
        Step.send(:remove_const, name)
        Step.const_set(name, old)
    end
end
