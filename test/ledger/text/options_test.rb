# frozen_string_literal: true

require "minitest/autorun"

require "ledger/text/options"

# Cases of choices, option_parts, option_code, label_fold,
# option_problem and choice, from check-ledger-questions.sh
# (the choice-* cases), check-ledger-awaits.sh (drop-not-an-answer,
# drop-per-item-stays) and check-ledger-write.sh (colon-option-refused,
# colon-in-meaning-ok).
class OptionsTest < Minitest::Test
    Options = Ledger::Text::Options

    MODE = ["A = fast; riskier", "B = slow; safe", "C = middle; fine"].freeze

    def test_split
        assert_equal %w[a b], Options.split("a|b")
        assert_equal ["A = a", "B = b"], Options.split(" A = a | B = b |")
    end

    def test_parts
        assert_equal ["A", "keep it", "costs a day"],
                     Options.parts("A = keep it; costs a day")
        assert_equal ["A", "keep it", ""], Options.parts("A = keep it")
        assert_equal ["B", "", ""], Options.parts("B")
    end

    def test_code
        assert_equal "A", Options.code("A = keep as is")
        assert_equal "drop", Options.code("drop")
    end

    def test_fold
        assert_equal Options.fold("Aa"), Options.fold("aa")
        assert_equal "a b", Options.fold("  A   B ")
    end

    def test_repr_as_python_quotes
        assert_equal "'A'", Options.repr("A")
        assert_equal "\"G'\"", Options.repr("G'")
        assert_equal "'a\\\\b'", Options.repr("a\\b")
        assert_equal "'G′'", Options.repr("G′")
    end

    def test_grammar_ok
        assert_nil Options.problem(["A = a", "B = b"])
        assert_nil Options.problem(MODE)
    end

    def test_colon_in_meaning_ok
        assert_nil Options.problem(
            ["A = doc (one line)", "B = cap (~4 files: route, tests)"]
        )
    end

    def test_long_label_refused
        label = "A label far too long for the picker"
        assert_equal "option 'A label far too long for the picker': a " \
                     "label is at most 24 characters without `;` or `?`; " \
                     "put the detail in its effect (`LABEL = what it does`)",
                     Options.problem(["#{label} = e; c"])
        assert_nil Options.problem(["#{"x" * 24} = a", "y = b"])
    end

    def test_semicolon_or_question_label_refused
        assert_match(/a label is at most 24/, Options.problem(["E; F = e; c"]))
        assert_match(/a label is at most 24/, Options.problem(["E? = e"]))
    end

    def test_effect_with_equals_refused
        assert_equal "option 'E': its effect holds ` = `; one " \
                     "`LABEL = effect` each",
                     Options.problem(["E = a = b; c"])
    end

    def test_same_label_folded_refused
        why = "two options share a label once case and spacing are " \
              "folded; rename one"
        assert_equal why, Options.problem(["Aa = a", "aa = b"])
        assert_equal why, Options.problem(["B = slow", "b = another"])
    end

    def test_same_effect_refused
        why = "two options share one effect; say what each does " \
              "differently, or drop one"
        assert_equal why, Options.problem(["X1 = same", "Y1 = Same"])
        assert_equal why, Options.problem(["A = middle; x", "E = middle; y"])
    end
end

# The `choice` edits and the shape check of a question's options.
class OptionsEditTest < Minitest::Test
    Options = Ledger::Text::Options

    MODE = OptionsTest::MODE

    def test_add_appends
        opts, why = Options.add(MODE, "D = other; odd")
        assert_nil why
        assert_equal MODE + ["D = other; odd"], opts
    end

    def test_add_refusals
        assert_equal "--add takes `LABEL = what it does`",
                     Options.add(MODE, "E").last
        assert_equal "--add takes `LABEL = what it does`",
                     Options.add(MODE, " ").last
    end

    def test_add_breaking_the_grammar_refused
        assert_match(/share a label/, Options.add(MODE, "b = another; x").last)
        assert_match(/share one effect/,
                     Options.add(MODE, "E = middle; x").last)
        assert_match(/label is at most 24/,
                     Options.add(MODE, "E; F = e; c").last)
        assert_match(/effect holds ` = `/,
                     Options.add(MODE, "E = a = b; c").last)
    end

    def test_add_question_mark_in_effect_is_the_pickers_g4
        assert_nil Options.add(MODE, "E = ok? yes; c").last
    end

    def test_drop_folds_label
        opts, why = Options.drop(MODE + ["D = other; odd"], "d")
        assert_nil why
        assert_equal MODE, opts
    end

    def test_drop_unknown_refused
        assert_equal "--drop Z: no such option (A, B, C)",
                     Options.drop(MODE, "Z").last
    end

    def test_drop_to_one_is_not_a_choice_here
        # the grammar of the set is option_problem's; two or more is
        # Picker's (G3), so one left passes this layer
        opts, why = Options.drop(["B = slow; safe", "C = middle; fine"], "B")
        assert_nil why
        assert_equal ["C = middle; fine"], opts
    end

    def test_shape_colon_option
        assert_equal ["an option with a colon; one answer per item is " \
                      "`items: a | b`"],
                     Options.shape_problems(["per item: A = a", "B = b"], [])
    end

    def test_shape_items_without_choices
        assert_equal ["`items:` without `choices:`"],
                     Options.shape_problems([], %w[S1 S2])
    end

    def test_shape_drop_and_ignore_refused
        why = ["drop/ignore is not an answer: the viewer always offers it"]
        assert_equal why, Options.shape_problems(["A = a", "drop = leave"], [])
        assert_equal why, Options.shape_problems(["A = a", "ignore"], [])
        assert_equal why, Options.shape_problems(["A = a", "Drop = x"], [])
    end

    def test_shape_drop_per_item_stays
        assert_empty Options.shape_problems(
            ["A = as is", "drop = skip it"], %w[S1 S2]
        )
    end

    def test_shape_clean
        assert_empty Options.shape_problems(["A = a", "B = b"], [])
    end
end
