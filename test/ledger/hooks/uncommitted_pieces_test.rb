# frozen_string_literal: true

require_relative "uncommitted_repo"

# uncommitted: what the ledger's pieces say. A piece awaiting commit, a
# piece out or one marked --no-commit keeps the stop quiet.
class UncommittedPiecesTest < HookTest
    include UncommittedRepo

    def test_a_piece_awaiting_commit_is_quiet
        dirty!
        piece_in(awaits: %w[commit])

        assert_equal Ledger::Hooks::Answer.pass, stop
    end

    def test_a_piece_out_is_quiet
        dirty!
        piece_in(status: "out")

        assert_equal Ledger::Hooks::Answer.pass, stop
    end

    def test_a_piece_marked_no_commit_is_quiet
        dirty!
        Ledger::Write.run(@journal, @address, "import", []) do |change|
            piece(change, no_commit: "an experiment")
        end

        assert_equal Ledger::Hooks::Answer.pass, stop
    end

    def test_a_piece_awaiting_another_word_still_sends_the_stop
        dirty!
        piece_in(awaits: %w[deploy])

        assert_equal 2, stop.status
    end
end
