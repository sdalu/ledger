# frozen_string_literal: true

require_relative "runner_test"

# self-routed, pieces-awaits, pieces-order, verified-by, and the pieces'
# part of titles, details and case-rated.
class PiecesChecksTest < CheckCase
    def test_a_piece_routed_to_its_own_project_fails_self_routed
        piece(model: nil, effort: nil, peer: "Alpha")

        assert_fails "self-routed",
                     "P1 is routed to this ledger's own session (alpha): " \
                     "keep it (kept: reason) or route it to a delegate"
    end

    def test_a_piece_routed_to_another_peer_passes
        piece(model: nil, effort: nil, peer: "beta")

        assert_passes "self-routed"
    end

    def test_start_on_a_piece_out_fails_pieces_awaits
        awaits(piece(status: "out", claimed_by: "s", **case_fields), "start")

        assert_fails "pieces-awaits", "P1 [out] awaits start, which begins " \
                                      "a planned or kept piece"
    end

    def test_a_finishing_word_on_a_piece_not_done_fails_pieces_awaits
        awaits(piece(**case_fields), "commit", "push")

        assert_fails "pieces-awaits", "P1 [planned] awaits commit, push, " \
                                      "which only finish a piece that is done"
    end

    def test_a_scope_for_a_word_not_awaited_fails_pieces_awaits
        id = piece(status: "verified", evidence: "ok", **case_fields)
        awaits(id, "commit")
        @rows.insert(:piece_scopes, piece_id: id, position: 0, word: "deploy",
                                    text: "ship it")

        assert_fails "pieces-awaits",
                     "P1 scope names deploy, which it does not await"
    end

    def test_waiting_for_a_dropped_piece_fails_pieces_order
        gone = piece(status: "dropped")
        after(piece, gone)

        assert_fails "pieces-order", "P2 waits for dropped P1"
    end

    def test_leaving_before_the_after_piece_is_settled_fails_pieces_order
        first = piece
        after(piece(status: "back"), first)

        assert_fails "pieces-order", "P2 [back] before P1 is verified"
    end

    def test_verified_by_its_own_route_fails_verified_by
        piece(status: "verified", evidence: "ok", skills: "ruby",
              verified_by: "sonnet, effort: low")
        piece(status: "verified", evidence: "ok", model: nil, effort: nil,
              peer: "beta", verified_by: "peer: beta")

        assert_fails "verified-by",
                     "P1 is verified by its own route (sonnet, effort: " \
                     "low); P2 is verified by its own route (peer: beta)"
    end

    def test_verified_by_me_passes
        piece(status: "verified", evidence: "ok", verified_by: "me")

        assert_passes "verified-by"
    end

    def test_an_out_piece_without_its_claim_is_refused
        assert_raises(Sequel::CheckConstraintViolation) do
            piece(status: "out")
        end
    end

    def test_a_verified_piece_without_its_verifier_is_refused
        assert_raises(Sequel::CheckConstraintViolation) do
            piece(status: "verified", evidence: "ok", verified_by: nil)
        end
    end

    def test_a_piece_title_of_ids_fails_titles_while_in_flight
        piece(title: "P3 O4")
        piece(title: "P3 O4", status: "verified", evidence: "ok")

        assert_fails "titles", "P1: #{Ledger::Text::Title::MOSTLY_IDS}"
    end

    def test_a_piece_detail_of_ids_fails_details
        piece(detail: "P3 P4 P5")

        assert_fails "details",
                     "P1: the detail is mostly ids; say in words what they " \
                     "stand for, or point to them with — see:"
    end

    def test_an_awaiting_piece_without_its_case_fails_case_rated
        awaits(piece(status: "kept", model: nil, effort: nil,
                     kept_reason: "mine"), "start")

        assert_fails "case-rated",
                     "P1: a piece awaiting the user's word without a " \
                     "`— problem:`; P1: a piece awaiting the user's word " \
                     "without a rated `— risk: N/10 — …`"
    end

    def case_fields = { problem: "p", risk: "2/10 — x", risk_rating: 2 }
end
