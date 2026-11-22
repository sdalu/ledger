# frozen_string_literal: true

require_relative "helper"

# `piece P<n> --commits`: after its status line, one line naming the
# started pieces the landing makes ready; none when it frees nobody.
class PieceReadyTest < CommandCase
    ROUTE = ["--route", "sonnet, effort: low"].freeze
    DONE = ["--status", "verified", "--verified-by", "me", "--evidence",
            "ran it", "--no-picture", "a wording change"].freeze
    SHA = "a1b2c3d"

    def setup
        super
        ok("piece", BETA, "new", "--title", "First", *ROUTE)
    end

    def follower(title, *)
        ok("piece", BETA, "new", "--title", title, *ROUTE, "--after", "P1", *)
    end

    def land = ok("piece", BETA, "P1", *DONE, "--commits", SHA)

    def test_the_landing_names_the_started_pieces_it_makes_ready
        follower("Second")
        follower("Third")

        assert_equal "now ready: P2, P3", land.lines.last.chomp
        assert_match(/\AStatus \(/, land.lines[-2])
    end

    def test_the_landing_names_nobody_when_it_frees_no_piece
        out = land

        assert_match(/\AStatus \(/, out.lines.last)
        refute_includes out, "now ready"
    end

    def test_a_held_piece_and_one_awaiting_its_start_are_not_named
        follower("Second", "--hold", "waits for the user")
        follower("Third", "--awaits", "start", "--problem", "p",
                 "--risk", "2/10 — a small change")

        refute_includes land, "now ready"
    end

    def test_a_piece_with_another_wait_unsettled_is_not_named
        ok("piece", BETA, "new", "--title", "Other", *ROUTE)
        follower("Second", "--after", "P1,P2")

        refute_includes land, "now ready"
    end
end
