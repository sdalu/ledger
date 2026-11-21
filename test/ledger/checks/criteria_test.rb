# frozen_string_literal: true

require_relative "runner_test"

# criteria and criteria-pieces.
class CriteriaChecksTest < CheckCase
    def test_no_criterion_fails_criteria
        db[:criteria].delete

        assert_fails "criteria", "need at least one `- [ ] D<n>: ...`"
    end

    def test_a_criterion_met_while_its_piece_is_out_fails
        id = piece(status: "out", claimed_by: "s")
        @rows.insert(:piece_links, piece_id: id, kind: "for", position: 0,
                                   criterion_id: db[:criteria].first[:id])

        assert_fails "criteria-pieces", "D1 met while P1 [out] serves it"
    end

    def test_an_unmet_criterion_may_be_served_by_a_blocked_piece
        id = piece(status: "blocked")
        crit = criterion
        @rows.insert(:piece_links, piece_id: id, kind: "for", position: 0,
                                   criterion_id: crit)

        assert_passes "criteria-pieces"
    end
end
