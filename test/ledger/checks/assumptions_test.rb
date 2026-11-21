# frozen_string_literal: true

require_relative "runner_test"

# assumptions-refuted: a piece in flight or an open question resting on
# a refuted assumption fails; settled pieces, closed questions and open
# or confirmed assumptions do not; the rule never refuses a write.
class AssumptionsChecksTest < CheckCase
    def test_a_piece_in_flight_on_a_refuted_assumption_fails
        %w[planned blocked deferred].each do |status|
            id = piece(status:, until: ("a release" if status == "deferred"))
            rests(assumption("refuted"), piece_id: id)
        end

        assert_fails "assumptions-refuted",
                     "P1 rests on A1 (refuted); P2 rests on A2 (refuted); " \
                     "P3 rests on A3 (refuted)"
    end

    def test_an_open_question_on_a_refuted_assumption_fails
        rests(assumption("refuted"), question_id: question)

        assert_fails "assumptions-refuted", "O1 rests on A1 (refuted)"
    end

    def test_open_and_confirmed_assumptions_pass
        id = piece
        rests(assumption("open"), piece_id: id)
        rests(assumption("confirmed"), piece_id: id)

        assert_passes "assumptions-refuted"
    end

    def test_a_settled_piece_or_a_closed_question_passes
        a = assumption("refuted")
        rests(a, piece_id: piece(status: "verified", evidence: "ran"))
        rests(a, piece_id: piece(status: "dropped"))
        rests(a, question_id: question(closed_at: 1))

        assert_passes "assumptions-refuted"
    end

    def test_the_write_path_does_not_compare_it
        rests(assumption("refuted"), piece_id: piece)

        names = Ledger::Checks.call(snapshot).map(&:first)
        refute_includes names, "assumptions-refuted"
    end

    def test_a_settled_assumption_without_its_fact_fails
        assumption("open")
        assumption("confirmed")
        assumption("refuted", fact: false)

        assert_fails "assumptions-settled", "A3 refuted without its fact"
    end

    private

    def assumption(state, fact: true)
        fact_id = fact_row if fact && state != "open"
        @rows.insert(:assumptions, n: @rows.next_id("A"), text: "it holds",
                                   check: "try it", state:, fact_id:)
    end

    def fact_row
        @rows.insert(:facts, n: @rows.next_id("F"), text: "seen",
                             pointer: "log")
    end

    def rests(assumption_id, **target)
        @rows.insert(:assumption_links, assumption_id:, **target)
    end
end
