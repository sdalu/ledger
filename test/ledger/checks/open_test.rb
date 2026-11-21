# frozen_string_literal: true

require_relative "runner_test"

# open-choices, open-described, open-picker, and the questions' part of
# titles, details and case-rated. A closed question is in none.
class OpenChecksTest < CheckCase
    def test_an_option_with_a_colon_fails_open_choices
        question(["per item: A = keep", "B = drop the cache"])

        assert_fails "open-choices",
                     "O1 (#{Ledger::Text::Options::COLON})"
    end

    def test_a_drop_option_fails_open_choices
        question(["A = keep it", "drop = forget it"])

        assert_fails "open-choices", "O1 (#{Ledger::Text::Options::DROP})"
    end

    def test_items_without_choices_fails_open_choices
        id = question([])
        @rows.insert(:question_items, question_id: id, position: 0,
                                      text: "S4")

        assert_fails "open-choices",
                     "O1 (#{Ledger::Text::Options::NO_CHOICES})"
    end

    def test_a_question_without_its_case_fails_open_described
        question(["A", "B = drop the cache"], problem: nil, recommend: nil)

        assert_fails "open-described",
                     "O1 needs `— problem:`, what A does (`X = what it " \
                     "does, what it costs`), `— recommend: X, why`"
    end

    def test_a_question_being_prepared_owes_no_pick
        prep = piece
        question(%w[A B], recommend: nil, by_id: prep)

        assert_passes "open-described"
    end

    def test_dropping_the_recommended_option_fails_open_picker
        id = question(["A = keep it", "B = drop it", "C = move it"])
        db[:question_choices].where(question_id: id, label: "A").delete

        assert_fails "open-picker",
                     "O1: recommend: 'A,' is not an option; `LABEL, why` " \
                     "with a label of choices (G5)"
    end

    def test_dropping_to_one_option_fails_open_picker
        id = question
        db[:question_choices].where(question_id: id, label: "B").delete

        assert_fails "open-picker",
                     "O1: one option is no choice (G3); give two to eight"
    end

    def test_a_question_mark_in_an_effect_fails_open_picker
        question(["A = keep it", "B = drop it?"])

        assert_fails "open-picker",
                     "O1: option 'B': #{Ledger::Text::Picker::G4_EFFECT}"
    end

    def test_two_questions_with_the_same_options_fail_open_picker
        question
        question

        assert_fails "open-picker",
                     "O1 and O2 offer the same options (G9); one question, " \
                     "or #{Ledger::Text::Picker::REPLACES}"
    end

    def test_a_closed_question_is_not_checked
        question(["A = keep it", "B = drop it?"], closed_at: 5, title: "O1")

        assert_empty Ledger::Checks.failures(snapshot, final: true)
    end

    def test_a_question_title_of_ids_fails_titles
        question(title: "O13 D1")

        assert_fails "titles", "O1: #{Ledger::Text::Title::MOSTLY_IDS}"
    end

    def test_a_question_detail_of_ids_fails_details
        question(detail: "P1 P2 P3 or?")

        assert_fails "details",
                     "O1: the detail is mostly ids; say in words what they " \
                     "stand for, or point to them with — see:"
    end

    def test_an_unrated_or_missing_risk_fails_case_rated
        question(risk: "slow", risk_rating: nil)
        question(["C = one", "D = two"], risk: nil, risk_rating: nil)

        assert_fails "case-rated",
                     "O1: an open question whose risk is unrated; " \
                     "O2: an open question without a `— risk: N/10 — …`"
    end
end
