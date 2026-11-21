# frozen_string_literal: true

require "minitest/autorun"

require "ledger/text/picker"

# Cases of picker_problems, picker_card, recommend_problem,
# recommended, contains_label and the G9 check, from
# check-ledger-questions.sh (grammar-g1 to g9, check-open-picker-*,
# dry-run-card, choice-add-question-mark-in-effect-refused).
module PickerHelper
    Picker = Ledger::Text::Picker

    def run_problems(opts, recommend: "", detail: "which?", items: [],
                     ready: true)
        Picker.problems(detail:, opts:, items:, recommend:, ready:)
    end

    def only(problems, text)
        assert_equal 1, problems.size, problems.inspect
        assert_match(/#{Regexp.escape(text)}/, problems.first)
    end
end

# Grammar rules G1 to G4 and G7.
class PickerGrammarTest < Minitest::Test
    include PickerHelper

    def test_clean_question
        assert_equal [[], []],
                     run_problems(["A = a", "B = b"], recommend: "A, x")
    end

    def test_g1_families
        out, = run_problems(
            ["A1 = a", "A2 = b", "B1 = c", "B2 = d"], recommend: "A1, x"
        )
        assert_equal ["options of families A, B in one question (G1); one " \
                      "question per family, `ledger ask … --replaces O<n>`"],
                     out
    end

    def test_g1_one_family_is_fine
        out, = run_problems(["A1 = a", "A2 = b", "B1 = c"],
                            recommend: "A1, x")
        assert_empty out
    end

    def test_g2_token
        out, = run_problems(["P = a", "P + spinner = b"], recommend: "P, x")
        assert_equal ["option 'P + spinner' holds the option 'P' as a " \
                      "whole token (G2); name each option apart"], out
    end

    def test_g2_prime_stays_on_its_letter
        out, = run_problems(["G = a", "G′ + spinner = b"],
                            recommend: "G, x")
        assert_empty out
    end

    def test_g3_one_option
        out, = run_problems(["H = a"], recommend: "H, x")
        assert_equal ["one option is no choice (G3); give two to eight"], out
    end

    def test_g3_nine_options
        opts = (1..9).map { "L#{it} = #{(96 + it).chr}" }
        out, = run_problems(opts, recommend: "L1, x")
        assert_equal ["9 options (G3: two to eight); split the question, " \
                      "`ledger ask … --replaces O<n>`"], out
    end

    def test_g3_seven_and_eight_warn
        opts = (1..7).map { "M#{it} = #{(96 + it).chr}" }
        out, warn = run_problems(opts, recommend: "M1, x")
        assert_empty out
        assert_equal ["7 options (G3: seven or eight is a lot to weigh)"], warn
        assert_equal ["8 options (G3: seven or eight is a lot to weigh)"],
                     run_problems(opts + ["M8 = h"], recommend: "M1, x").last
        assert_empty run_problems(opts.first(6), recommend: "M1, x").last
    end

    def test_g4_two_questions
        detail = "which one? or that one?"
        out, = run_problems(["N = a", "O = b"], recommend: "N, x", detail:)
        only out, "(G4: one `?` outside backticks and quotes)"
    end

    def test_g4_quoted_question_marks_ok
        detail = "is `a?b` kept, or \"c?\" instead?"
        out, = run_problems(["Q = a", "R = b"], recommend: "Q, x",
                                                detail:)
        assert_empty out
    end

    def test_g4_curly_quoted_ok
        out, = run_problems(["Q = a", "R = b"], recommend: "Q, x",
                                                detail: "is “c?” kept, or not?")
        assert_empty out
    end

    def test_g4_effect_question
        out, = run_problems(["S = what now?", "T = b"], recommend: "S, x")
        assert_equal ["option 'S': its effect holds a `?` (G4); say what " \
                      "it does, not what it asks"], out
    end
end

# Recommend rule G5.
class PickerRecommendTest < Minitest::Test
    include PickerHelper

    Recommend = Ledger::Text::Recommend

    def test_g5_no_why
        out, = run_problems(["U = a", "V = b"], recommend: "U")
        assert_equal ["recommend: 'U' gives no why; `U, why` (G5)"], out
    end

    def test_g5_not_an_option
        out, = run_problems(["U = a", "V = b"], recommend: "W, x")
        assert_equal ["recommend: 'W,' is not an option; `LABEL, why` with " \
                      "a label of choices (G5)"], out
    end

    def test_g5_waits_while_a_piece_prepares_the_question
        out, = run_problems(["U = a", "V = b"], recommend: "W, x",
                                                ready: false)
        assert_empty out
    end

    def test_g5_items_one_pick_per_item
        out, = run_problems(["U = a", "V = b"], recommend: "S1 U",
                                                items: %w[S1 S2])
        assert_equal ["recommend: one option for each item, not for S2 " \
                      "(G5)"], out
    end

    def test_g5_items_pairs_ok
        out, = run_problems(["U2 = a", "V2 = b"],
                            recommend: "S1 U2, S2 V2", items: %w[S1 S2])
        assert_empty out
    end

    def test_g5_items_pair_names_no_option
        out, = run_problems(["U = a", "V = b"], recommend: "S1 U, S2 Z",
                                                items: %w[S1 S2])
        assert_equal ["recommend: 'S2 Z' names no option (G5)"], out
    end

    def test_g5_items_pair_starts_with_no_item
        out, = run_problems(["U = a", "V = b"], recommend: "S9 U, S2 V",
                                                items: %w[S1 S2])
        assert_equal ["recommend: 'S9 U' starts with no item (S1, S2); " \
                      "`S1 A, S2 B` (G5)"], out
    end

    def test_one_item_plain_recommend
        out, = run_problems(["C9 = a", "D9 = b"], recommend: "C9, cheap",
                                                  items: ["S9"])
        assert_empty out
    end

    def test_g7_items_need_choices
        out, = run_problems([], items: %w[S1 S2])
        assert_equal ["`items:` without `choices:` (G7); give the answers " \
                      "offered per item"], out
    end

    def test_no_options_no_items_is_a_question_in_words
        assert_equal [[], []], run_problems([])
    end

    def test_recommend_label_with_spaces
        out, = run_problems(["Keep it = a", "Drop it = b"],
                            recommend: "keep it, because")
        assert_empty out
    end

    def test_recommended
        opts = ["A = as drawn", "B = smaller"]
        assert_equal({ "a" => "x" }, Recommend.recommended("A, x", opts, []))
        assert_equal({ "a" => "" }, Recommend.recommended("A", opts, []))
        assert_equal({}, Recommend.recommended("C, x", opts, []))
        assert_equal({ "a" => "", "b" => "" },
                     Recommend.recommended("S1 A, S2 B", opts, %w[S1 S2]))
    end
end

# The card and the G9 comparison of two questions.
class PickerCardTest < Minitest::Test
    include PickerHelper

    Card = Ledger::Text::Card

    def test_card
        issues = run_problems(["C = new a", "D = new b"], recommend: "C, x")
        assert_equal ["picker O5: 2 options", "  C = new a  <- recommended",
                      "  D = new b"],
                     Card.lines("O5", ["C = new a", "D = new b"], [], "C, x",
                                issues)
    end

    def test_card_with_cost_items_and_warning
        opts = ["A = a; dear", "B = b"]
        card = Card.lines("O1", opts, %w[S1 S2], "S1 A, S2 B",
                          [["boom"], ["careful"]])
        assert_equal ["picker O1: 2 options for each of S1, S2",
                      "  A = a; dear  <- recommended",
                      "  B = b  <- recommended",
                      "  recommended: S1 A, S2 B",
                      "  warning: careful", "  refused: boom"], card
    end

    def test_card_without_choices
        assert_equal ["picker O2: none (no choices:, the user answers in " \
                      "words)"], Card.lines("O2", [], [], "", [[], []])
    end

    def test_g9_same_options
        qs = [["O90", ["K = a", "L = b"]], ["O91", ["l = b", "k = a"]]]
        assert_equal ["O90 and O91 offer the same options (G9); one " \
                      "question, or `ledger ask … --replaces O<n>`"],
                     Picker.duplicates(qs)
    end

    def test_g9_same_letters_other_effects_ok
        qs = [["O92", ["A = keep it", "B = drop it"]],
              ["O93", ["A = the left", "B = the right"]]]
        assert_empty Picker.duplicates(qs)
    end

    def test_g9_questions_without_options_ignored
        assert_empty Picker.duplicates([["O1", []], ["O2", []]])
    end

    def test_contains_label
        assert Picker.contains_label?("P + spinner", "P")
        refute Picker.contains_label?("P", "P")
        refute Picker.contains_label?("G′ + spinner", "G")
        refute Picker.contains_label?("Pa", "P")
        assert Picker.contains_label?("Keep the HEADER", "the header")
    end
end
