# frozen_string_literal: true

require_relative "json_test"

# The fixture with two assumptions: A1 open, resting on F1, under P2 and
# O1; A2 refuted by F1. Each carries its fact, what it rests on and what
# rests on it; each piece and question the assumptions it rests on; each
# piece when an event last touched it.
class JsonAssumptionsTest < JsonCase
    def more(change)
        super
        one = assumption(change, text: "it scales", check: "load it",
                                 state: "open")
        change.insert(:assumption_sees, assumption_id: one, position: 0,
                                        fact_id: 1)
        change.insert(:assumption_links, assumption_id: one, piece_id: 2)
        change.insert(:assumption_links, assumption_id: one, question_id: 1)
        assumption(change, text: "one host", check: "ask ops",
                           state: "refuted", fact_id: 1)
    end

    def assumption(change, **)
        change.insert(:assumptions, n: change.next_id("A"), **)
    end

    def test_an_assumption_carries_its_fact_sees_and_what_rests_on_it
        build
        one, two = document[:assumptions]

        assert_equal({ id: "A1", text: "it scales", check: "load it",
                       state: "open", fact: nil, see: %w[F1],
                       for: %w[P2 O1],
                       line: "- A1 [open] it scales — check: load it — " \
                             "see: F1 — for: P2, O1" }, one)
        assert_equal "- A2 [refuted] one host — check: ask ops — by: F1",
                     two[:line]
    end

    def test_pieces_and_questions_name_the_assumptions_they_rest_on
        build

        assert_equal([[], ["A1"], []],
                     document[:pieces].map { it[:rests_on_assumptions] })
        assert_equal ["A1"], document[:questions][0][:rests_on_assumptions]
    end

    def test_a_piece_carries_when_an_event_last_touched_it
        build
        first = "2023-11-14T23:13:20+01:00"

        assert_equal([first, first, "2023-11-14T23:15:20+01:00"],
                     document[:pieces].map { it[:touched_at] })
    end

    def test_the_status_line_names_the_open_ones
        build

        assert_includes document[:status], "out: P3 · assuming: A1 · " \
                                           "stalled: P3"
    end
end
