# frozen_string_literal: true

require_relative "helper"

# A question's line under Open, its fields in `ask`'s order.
class QuestionLineTest < RenderTest
    def test_title_and_detail_with_a_colon_and_a_space
        assert_equal "- O1: Title 1: What now?", question_text
    end

    def test_a_case_with_problem_and_risk
        assert_equal "- O1: Title 1: What now? — problem: it is slow — " \
                     "risk: 4/10 — a day lost",
                     question_text(problem: "it is slow",
                                   risk: "4/10 — a day lost")
    end

    def test_r7_choices_are_label_effect_cost_joined_by_pipes
        snap = snapshot do |change|
            id = question(change)
            choices(change, id,
                    [["A", "keep it", "a day"], ["B", "drop it", nil]])
        end

        assert_equal "- O1: Title 1: What now? — choices: A = keep it; " \
                     "a day | B = drop it", line(snap, "O1")
    end

    def test_an_option_that_is_only_a_label
        snap = snapshot do |change|
            choices(change, question(change),
                    [["A", nil, nil], ["B", nil, nil]])
        end

        assert_includes line(snap, "O1"), " — choices: A | B"
    end

    def test_r6_items_before_choices_then_recommend_by_and_see
        snap = snapshot { |change| full_question(change) }

        assert_equal "- O1: Title 1: What now? — problem: pr — risk: " \
                     "3/10 — r — items: S1 | S2 — choices: A = a; x | B = b " \
                     "— recommend: A, because — by: P1 — see: F1, C1, D1, P1",
                     line(snap, "O1")
    end

    def test_mockup_name_comes_last
        snap = snapshot do |change|
            id = question(change)
            change.insert(:question_pictures, question_id: id, position: 0,
                                              name: "layout")
        end

        assert_equal "- O1: Title 1: What now? — mockup: layout",
                     line(snap, "O1")
    end

    def test_mockup_pending_names_its_piece
        snap = snapshot do |change|
            piece_id = piece(change)
            id = question(change)
            change.insert(:question_pictures, question_id: id, position: 0,
                                              pending_id: piece_id)
        end

        assert_equal "- O1: Title 1: What now? — mockup: pending (P1)",
                     line(snap, "O1")
    end

    def test_the_prose_after_a_link_comes_before_the_mockup
        snap = snapshot do |change|
            id = question(change, tail: " — asked turn 3")
            change.insert(:question_pictures, question_id: id, position: 0,
                                              name: "m")
        end

        assert_equal "- O1: Title 1: What now? — asked turn 3 — mockup: m",
                     line(snap, "O1")
    end

    def test_the_open_section
        out = text do |change|
            goal(change)
            2.times { question(change) }
        end

        assert_includes out, "Open:\n- O1: Title 1: What now?\n" \
                             "- O2: Title 2: What now?\n\nOut of"
    end

    private

    def choices(change, id, options)
        options.each_with_index do |(label, effect, cost), i|
            change.insert(:question_choices, question_id: id, position: i,
                                             label:, effect:, cost:)
        end
    end

    def full_question(change)
        piece_id = piece(change)
        crit = criterion(change)
        id = question(change, problem: "pr", risk: "3/10 — r",
                              recommend: "A, because", by_id: piece_id)
        choices(change, id, [%w[A a x], ["B", "b", nil]])
        change.insert(:question_items, question_id: id, position: 0, text: "S1")
        change.insert(:question_items, question_id: id, position: 1, text: "S2")
        sees(change, id, crit, piece_id)
    end

    def sees(change, id, crit, piece_id)
        fact = change.insert(:facts, n: change.next_id("F"), text: "t",
                                     pointer: "p")
        cons = change.insert(:constraints, n: change.next_id("C"), text: "t",
                                           quote: "q")
        [{ fact_id: fact }, { constraint_id: cons }, { criterion_id: crit },
         { piece_id: }].each_with_index do |target, i|
            change.insert(:question_sees, question_id: id, position: i,
                                          **target)
        end
    end
end
