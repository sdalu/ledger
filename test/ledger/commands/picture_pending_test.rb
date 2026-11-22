# frozen_string_literal: true

require_relative "mockup_test"

# `piece P<n> --picture-pending WHY` and pictures-fresh through the
# commands: the warning on a plain check, the failure on --final, the
# redraw announced and shown, cleared by the next picture or by '', and
# a piece awaiting commit refused while stale.
class PicturePendingTest < MockupCase
    CASE = ["--problem", "the order is lost", "--risk",
            "2/10 — a reload"].freeze

    def setup
        super
        ok("piece", BETA, "new", "--title", "Fix the reorder", "--route",
           "sonnet, effort: low", "--plan", "sort by rank", *CASE)
        side("b.png", "before")
        side("a.png", "after")
        earlier
    end

    def side(name, role, *)
        ok("mockup", BETA, file(name), "--piece", "P1", "--#{role}", *)
    end

    # Every event so far a minute earlier: what the next command writes
    # comes after the pictures, whatever the clock's resolution.
    def earlier = db[:events].update(at: Sequel[:at] - 60_000)

    def piece(*) = ok("piece", BETA, "P1", *)

    def fresh(*flags)
        _, out, = cli("check", "--peek", *flags, BETA)
        out.lines(chomp: true).grep(/ pictures-fresh/).first
    end

    def test_a_plan_changed_after_the_pictures_warns_and_fails_final
        piece("--plan", "sort by rank, then by name")

        assert_match(/\Awarn pictures-fresh -- P1: plan changed after its /,
                     fresh)
        assert_equal 0, cli("check", "--peek", BETA).first
        assert_match(/\AFAIL pictures-fresh -- P1: plan changed /,
                     fresh("--final"))
    end

    def test_status_and_evidence_leave_it_fresh
        piece("--status", "verified", "--verified-by", "me", "--evidence",
              "the suite passes")

        assert_equal "ok   pictures-fresh", fresh
    end

    def test_pending_is_announced_shown_and_cleared_by_the_next_picture
        out = piece("--plan", "sort by name", "--picture-pending",
                    "the order changed")

        assert_includes out, "— picture: being redrawn (the order changed)"
        assert_equal "warn pictures-fresh -- P1: picture being redrawn " \
                     "(the order changed)", fresh
        side("a2.png", "after", "--replace")
        assert_nil db[:pieces].where(n: 1).get(:picture_pending)
        assert_equal "ok   pictures-fresh", fresh
    end

    def test_pending_is_cleared_by_an_empty_why
        piece("--picture-pending", "the order changed")
        refute_includes piece("--picture-pending", ""), "picture:"
        assert_nil db[:pieces].where(n: 1).get(:picture_pending)
    end

    def test_holds_clears_it_and_a_later_rewording_stales_it_again
        out = piece("--plan", "sort by name", "--picture-holds",
                    "the list looks the same")
        assert_includes out, "— picture: holds (the list looks the same)"
        assert_equal "ok   pictures-fresh", fresh
        earlier
        piece("--plan", "sort by rank again")

        assert_match(/\Awarn pictures-fresh -- P1: plan changed /, fresh)
        assert_refused("piece", BETA, "P1", "--picture-pending", "a",
                       "--picture-holds", "b", "are exclusive")
    end

    def test_awaiting_commit_while_stale_is_refused
        piece("--plan", "sort by name")
        earlier
        piece("--status", "verified", "--verified-by", "me", "--evidence",
              "the suite passes")
        assert_refused("piece", BETA, "P1", "--awaits", "commit",
                       "pictures-fresh -- P1 (awaits commit): plan changed")
        assert_refused("piece", BETA, "P1", "--awaits", "commit",
                       "— set --picture-pending WHY, --picture-holds WHY, " \
                       "or place a new picture first")
    end

    def test_an_awaiting_plan_edit_needs_the_redraw_in_the_same_write
        piece("--status", "verified", "--verified-by", "me", "--evidence",
              "the suite passes", "--awaits", "commit")
        earlier
        assert_refused("piece", BETA, "P1", "--plan", "sort by name",
                       "plan changed after its last picture (2026-")
        piece("--plan", "sort by name", "--picture-pending", "new order")

        assert_match(/\AFAIL pictures-fresh -- P1: plan changed .*; P1: /,
                     fresh("--final"))
        ok("undo", BETA)
        assert_equal "ok   pictures-fresh", fresh
    end

    def test_awaiting_commit_once_redrawn_passes
        piece("--plan", "sort by name", "--status", "verified",
              "--verified-by", "me", "--evidence", "the suite passes")
        earlier
        side("a2.png", "after", "--replace")
        earlier
        piece("--awaits", "commit")

        assert_equal "ok   pictures-fresh", fresh
    end
end
