# frozen_string_literal: true

require_relative "helper"

# A piece's line: status, route, title and detail, and the fields in
# `piece`'s order.
class PieceLineTest < RenderTest
    %w[planned out back blocked dropped].each do |status|
        define_method("test_status_#{status}_in_brackets") do
            assert_equal "- P1 [#{status}] sonnet, effort: low — Piece 1",
                         piece_text(status:)
        end
    end

    def test_verified_carries_its_evidence_last
        assert_equal "- P1 [verified] sonnet, effort: low — Piece 1 — " \
                     "evidence: it ran", piece_text(status: "verified",
                                                    evidence: "it ran")
    end

    def test_kept_has_its_reason_in_the_status_and_no_route
        assert_equal "- P1 [kept: brief >= work] — Piece 1",
                     piece_text(status: "kept", kept_reason: "brief >= work",
                                model: nil, effort: nil, dash: true)
    end

    def test_deferred_carries_its_condition_first
        assert_equal "- P1 [deferred] sonnet, effort: low — Piece 1 — " \
                     "until: three closures — plan: judge them",
                     piece_text(status: "deferred", until: "three closures",
                                plan: "judge them")
    end

    def test_kept_written_without_a_dash_keeps_none
        assert_equal "- P1 [kept: mine] Piece 1",
                     piece_text(status: "kept", kept_reason: "mine",
                                model: nil, effort: nil, dash: false)
    end

    def test_route_with_skills
        assert_equal "- P1 [planned] opus, effort: high, skills: c, ruby " \
                     "— Piece 1",
                     piece_text(model: "opus", effort: "high",
                                skills: "c, ruby")
    end

    def test_route_of_a_peer
        assert_equal "- P1 [out] peer: Skills:sinatra — Piece 1",
                     piece_text(status: "out", model: nil, effort: nil,
                                peer: "Skills:sinatra", claimed_by: "s1")
    end

    def test_r8_title_and_detail_are_joined_by_a_colon_and_a_space
        assert_equal "- P1 [planned] sonnet, effort: low — Cache: the " \
                     "detail", piece_text(title: "Cache", detail: "the detail")
    end

    def test_pieces_section_lists_them_in_order
        out = text do |change|
            goal(change)
            2.times { piece(change) }
        end

        assert_includes out, "Pieces:\n- P1 [planned] sonnet, effort: low " \
                             "— Piece 1\n- P2 [planned] sonnet, effort: low " \
                             "— Piece 2\n\nOpen:"
    end
end
