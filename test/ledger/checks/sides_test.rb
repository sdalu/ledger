# frozen_string_literal: true

require_relative "runner_test"

# pictures: a piece awaiting commit, deploy, push or merge has a before
# and an after placed, or a reason for none.
class SidesChecksTest < CheckCase
    def done = piece(status: "verified", evidence: "ok")

    def picture(piece_id, role)
        name = "#{role}-#{piece_id}.png"
        @rows.insert(:pictures, name:, path: "", type: "image/png",
                                sha256: Ledger::Pictures.blob(db, "png"))
        @rows.insert(:piece_pictures, piece_id:, position: 0, role:, name:)
    end

    def test_a_finishing_word_without_pictures_fails
        awaits(done, "commit", "push")

        assert_fails "pictures", "no before/after: P1 (awaits commit, push)"
    end

    def test_one_side_is_not_enough
        id = done
        awaits(id, "merge")
        picture(id, "before")

        assert_fails "pictures", "no before/after: P1 (awaits merge; has " \
                                 "before)"
    end

    def test_a_pair_passes
        id = done
        awaits(id, "deploy")
        picture(id, "before")
        picture(id, "after")

        assert_passes "pictures"
    end

    def test_a_reason_passes
        awaits(piece(status: "verified", evidence: "ok",
                     no_picture: "a rename"), "commit")

        assert_passes "pictures"
    end

    def test_start_and_other_are_exempt
        id = piece
        @rows.insert(:piece_awaits, piece_id: id, position: 0, word: "start")
        @rows.insert(:piece_awaits, piece_id: id, position: 1, word: "other",
                                    what: "a look")

        assert_passes "pictures"
    end
end
