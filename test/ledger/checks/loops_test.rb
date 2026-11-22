# frozen_string_literal: true

require_relative "runner_test"

# question-loop: an open question asked by a piece that awaits the
# user's word, which moves only once given it.
class LoopsChecksTest < CheckCase
    LINE = "O1 waits on P1, which waits on your start: clear the link " \
           "with ledger ask PATH O1 --by none, or give P1 its word"

    def first_question = derive.open_questions.first

    def test_a_question_by_a_piece_awaiting_start_fails_plain_and_final
        by = piece
        awaits(by, "start")
        question(by_id: by)

        assert_fails "question-loop", LINE
        assert_fails "question-loop", LINE, final: true
    end

    def test_a_question_by_a_piece_awaiting_nothing_passes_and_prepares
        question(by_id: piece)

        assert_passes "question-loop"
        assert_equal "P1", derive.ref(derive.preparer(first_question))
    end

    def test_a_loop_makes_the_question_answerable
        by = piece
        awaits(by, "start")
        question(by_id: by)

        assert derive.answerable?(first_question)
    end

    def test_a_closed_question_is_not_a_loop
        by = piece
        awaits(by, "start")
        question(by_id: by, closed_at: 1)

        assert_passes "question-loop"
    end
end
