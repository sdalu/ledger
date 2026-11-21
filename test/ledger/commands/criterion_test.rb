# frozen_string_literal: true

require_relative "helper"

# `criterion`: mark, reword and add the Done-when lines.
class CriterionTest < CommandCase
    def test_met_marks_it_with_its_evidence
        out = ok("criterion", BETA, "D1", "--met", "ran it")
        assert_equal "- [x] D1: <a check something other than opinion can " \
                     "pass> — evidence: ran it", out.lines.first.chomp
        assert_includes out.lines.last, "criteria 1/1"
    end

    def test_unmet_marks_it_with_its_reason
        ok("criterion", BETA, "D1", "--met", "ran it")
        assert_includes ok("criterion", BETA, "D1", "--unmet", "gone"),
                        "- [-] D1: <a check"
        assert_equal [nil, "gone"],
                     db[:criteria].select_map(%i[evidence why]).first
    end

    def test_text_rewords_and_keeps_the_mark
        ok("criterion", BETA, "D1", "--met", "ran it")
        out = ok("criterion", BETA, "D1", "--text", "tests pass")
        assert_equal "- [x] D1: tests pass — evidence: ran it",
                     out.lines.first.chomp
    end

    def test_new_adds_the_next_unmarked_criterion_and_prints_its_id
        out = ok("criterion", BETA, "new", "--text", "docs match")
        assert_equal ["D2", "- [ ] D2: docs match"],
                     out.lines(chomp: true)[0..1]
    end

    def test_a_dry_run_writes_nothing
        before = state
        out = ok("criterion", BETA, "D1", "--met", "x", "--dry-run")
        assert_includes out, "dry run: nothing written"
        assert_equal before, state
    end

    def test_the_target_must_be_a_criterion_that_exists
        assert_refused("criterion", BETA, "F1", "--met", "x",
                       "the target is D<n>")
        assert_refused("criterion", BETA, "D9", "--met", "x",
                       "D9 is not a criterion under Done when")
    end

    def test_an_empty_value_is_refused
        assert_refused("criterion", BETA, "D1", "--met", " ",
                       "none may be empty")
        assert_refused("criterion", BETA, "D1", "--text", " ",
                       "--text is empty")
        assert_refused("criterion", BETA, "new", "--text", " ",
                       "--text is empty")
    end

    def test_text_goes_alone
        assert_refused("criterion", BETA, "D1", "--text", "t", "--met", "x",
                       "--text goes alone, without --met or --unmet")
        assert_refused("criterion", BETA, "new", "--text", "t", "--met", "x",
                       "new takes --text alone")
        assert_refused("criterion", BETA, "D1", "--met", "x", "--unmet", "y",
                       "give one of --met, --unmet, --unmark, --text")
    end

    def marks = db[:criteria].first.values_at(:mark, :evidence, :why)

    def test_unmark_takes_a_mark_back_and_clears_its_reason
        ok("criterion", BETA, "D1", "--met", "ran it")
        ok("criterion", BETA, "D1", "--unmark")

        assert_equal [" ", nil, nil], marks
        ok("criterion", BETA, "D1", "--unmet", "out of reach")
        ok("criterion", BETA, "D1", "--unmark")

        assert_equal [" ", nil, nil], marks
    end

    def test_unmark_is_refused_on_a_criterion_not_marked
        assert_refused("criterion", BETA, "D1", "--unmark",
                       "D1 is not marked: nothing to unmark")
    end

    def test_unmark_goes_alone
        %w[--met --unmet --text].each do |flag|
            assert_refused("criterion", BETA, "D1", "--unmark", flag, "x",
                           "give one of --met, --unmet, --unmark, --text")
        end
        assert_refused("criterion", BETA, "new", "--text", "t", "--unmark",
                       "new takes --text alone")
    end

    def test_a_met_criterion_while_its_piece_is_unfinished_is_refused
        piece_serving(1)
        assert_refused("criterion", BETA, "D1", "--met", "x",
                       "criterion: refused, criteria-pieces -- D1 met while " \
                       "P1 [planned] serves it")
    end
end
