# frozen_string_literal: true

require "json"

require_relative "helper"

# `piece P<n> --irreversible`: stored on the piece, shown bare on its line
# after its awaits, cleared by --no-irreversible; show --json gives the
# step risk it raises and the work risk beside it.
class IrreversibleTest < CommandCase
    ANNOUNCE = "ANNOUNCE\nWHAT: w\nWHY: y\nWHICH: sonnet, effort: low\n" \
               "RISK: 6/10 — a caller missed\nMODE: attended\n"

    def setup
        super
        ok("piece", BETA, "new", "--title", "Ship the sort", "--route",
           "sonnet, effort: low", "--status", "verified", "--verified-by",
           "me", "--evidence", "suite green", "--problem", "not pushed",
           "--risk", "3/10 — the sort waits", "--no-picture", "wording",
           "--awaits", "commit, push")
    end

    def piece(*) = ok("piece", BETA, "P1", *)

    def json
        JSON.parse(ok("show", BETA, "--json"))["pieces"].first
    end

    def test_the_flag_is_stored_and_shown_after_the_awaits
        out = piece("--irreversible")

        assert_includes out, "— awaits: commit, push — irreversible"
        assert db[:pieces].where(n: 1).get(:irreversible)
    end

    def test_no_irreversible_clears_it
        piece("--irreversible")

        refute_includes piece("--no-irreversible"), "irreversible"
        refute db[:pieces].where(n: 1).get(:irreversible)
    end

    def test_the_step_risk_is_the_highest_word_raised_by_three
        assert_equal 4, json["step_risk"]
        piece("--irreversible")

        assert_equal [true, 7], json.values_at("irreversible", "step_risk")
    end

    def test_the_work_risk_is_the_piece_own_until_a_dispatch_rates_it
        assert_equal 3, json["work_risk"]
        file = File.join(@dir, "announce.txt")
        File.write(file, ANNOUNCE)
        piece("--announce", file)

        assert_equal 6, json["work_risk"]
    end

    def test_a_piece_awaiting_no_weighed_word_has_no_step_risk
        piece("--awaits", "other (a look at the shots)")

        assert_nil json["step_risk"]
    end
end
