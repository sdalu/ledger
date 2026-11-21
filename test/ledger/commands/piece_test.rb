# frozen_string_literal: true

require_relative "helper"

# A `piece` test: the session variable out of the way, a piece added
# with a route, a new one refused.
class PieceCase < CommandCase
    ROUTE = ["--route", "sonnet, effort: medium"].freeze
    NEW = ["new", "--title", "Build the parser"].freeze
    CASE = ["--problem", "the tree is dirty", "--risk",
            "3/10 — a stray file"].freeze

    def setup
        super
        @session = ENV.delete("CLAUDE_CODE_SESSION_ID")
    end

    def teardown
        ENV.delete("CLAUDE_CODE_SESSION_ID")
        ENV["CLAUDE_CODE_SESSION_ID"] = @session if @session
        super
    end

    def add(*argv) = ok("piece", BETA, *NEW, *ROUTE, *argv)
    def refused(*argv, message) = assert_refused("piece", BETA, *argv, message)
    def row(n = 1) = db[:pieces].where(ledger_id: @beta, n:).first
end

# `piece`: a piece added or changed, its route, title, links, words and
# scope, and the led_to edge of --by.
class PieceTest < PieceCase
    def test_a_new_piece_prints_its_id_then_its_line
        out = add("--what", "its grammar", "--for", "D1",
                  "--done-when", "tests pass")
        assert_equal ["P1", "- P1 [planned] sonnet, effort: medium — " \
                            "Build the parser: its grammar — done when: " \
                            "tests pass — for: D1"],
                     out.lines(chomp: true)[0..1]
        assert_match(/\AStatus — /, out.lines.last)
    end

    def test_a_route_with_skills_and_a_peer_route
        add("--route", "opus, effort: high, skills: c, ruby")
        assert_equal %w[opus high], row.values_at(:model, :effort)
        assert_equal "c, ruby", row[:skills]
        ok("piece", BETA, "P1", "--route", "peer: other-session")
        assert_equal ["other-session", nil], row.values_at(:peer, :model)
    end

    def test_kept_clears_the_route
        add("--status", "kept: the user keeps it")
        assert_equal ["kept", "the user keeps it", nil],
                     row.values_at(:status, :kept_reason, :model)
        assert_includes markdown,
                        "- P1 [kept: the user keeps it] — Build the parser"
    end

    def test_the_target_and_the_piece
        refused("X1", "--title", "a b", "the target is `new` or P<n>")
        refused("P4", "--plan", "x", "no P4 under Pieces in #{BETA}")
        refused("new", *ROUTE, "--title is required for a new piece")
    end

    def test_title_and_detail_rules
        refused("new", "--title", "O13 D1", *ROUTE,
                "piece: the title is mostly ids")
        refused(*NEW, "--what", "P1 P2 P3", *ROUTE,
                "piece: the detail is mostly ids")
    end

    def test_a_piece_needs_a_route_unless_kept
        refused(*NEW, "--route (`sonnet, effort: medium")
        refused(*NEW, "--route", "gpt, effort: lots", "--route (`sonnet")
        refused(*NEW, "--route", "gpt", "--status", "kept: x",
                "--route (`sonnet")
        refused(*NEW, "--status", "kept:", "'kept: REASON' says why")
        refused(*NEW, *ROUTE, "--status", "doing", "--status doing: one of")
    end

    def test_awaiting_needs_a_problem_and_a_rated_risk
        refused(*NEW, *ROUTE, "--awaits", "start",
                "a piece awaiting the user's word gives --problem")
        refused(*NEW, *ROUTE, "--awaits", "start", "--problem", "p",
                "--risk", "bad", "gives --risk")
        refused(*NEW, *ROUTE, *CASE, "--awaits", "ship", "--awaits: ship")
    end

    def test_awaits_and_scope_are_written_in_their_spelling
        add(*CASE, "--awaits", "start,other (look at it)", "--scope",
            "start = begin it")
        assert_includes markdown, "— scope: start = begin it"
        assert_includes markdown, "— awaits: start, other (look at it)"
    end

    def test_scope_grammar_and_words_not_awaited
        refused(*NEW, *ROUTE, *CASE, "--awaits", "start", "--scope", "start",
                "--scope is `WORD = what it authorises`")
        refused(*NEW, *ROUTE, *CASE, "--awaits", "start", "--scope",
                "deploy = x", "--scope names deploy, which the piece does " \
                              "not await (awaits: start)")
    end

    def test_an_awaited_word_kept_keeps_its_row
        add(*CASE, "--awaits", "start, other (a look)")
        first = db[:piece_awaits].order(:id).first[:id]
        ok("piece", BETA, "P1", "--awaits", "start")
        assert_equal [first], db[:piece_awaits].select_map(:id)
    end

    def test_links_name_items_of_their_kind_in_this_ledger
        add
        refused("P1", "--after", "D1", "--after takes P ids, not D1")
        refused("P1", "--for", "D7", "D7 is not this ledger's")
        add("--after", "P1")
        assert_includes markdown, "— after: P1"
    end

    def test_by_writes_the_led_to_edge
        ok("decide", BETA, "build it", "--by", "user")
        add("--by", "X1")
        assert_equal %w[led_to X P],
                     db[:links].first.values_at(:kind, :from_kind, :to_kind)
        refused("P1", "--by", "P1", "--by takes a decision id, X<n>")
        refused("P1", "--by", "X9", "X9 is not this ledger's")
    end
end

# `piece --status`: the claim of out (U12), the verifier of verified
# (U11), a dry run, and the own id matched whole.
class PieceStatusTest < PieceCase
    def test_out_needs_a_session
        add
        refused("P1", "--status", "out", "--status out needs a session id")
    end

    def test_out_claims_and_another_session_is_refused
        add
        ok("piece", BETA, "P1", "--status", "out", "--session", "s1")
        assert_equal %w[out s1], row.values_at(:status, :claimed_by)
        ENV["CLAUDE_CODE_SESSION_ID"] = "s2"
        refused("P1", "--status", "out", "P1 is out under s1 since")
        ok("piece", BETA, "P1", "--status", "back")
        assert_equal ["back", nil], row.values_at(:status, :claimed_by)
    end

    # A session resuming another's work takes the claim over: the piece
    # stays out, and no return is recorded.
    def test_claim_moves_an_out_piece_to_this_session
        add
        ok("piece", BETA, "P1", "--status", "out", "--session", "s1")
        out = ok("piece", BETA, "P1", "--claim", "--session", "s2")

        assert_equal "claimed: P1 from s1", out.lines.first.chomp
        assert_equal %w[out s2], row.values_at(:status, :claimed_by)
        assert_equal 0, db[:piece_returns].count
    end

    def test_claim_is_refused_off_an_out_piece_and_with_a_status
        add
        refused("P1", "--claim", "--session", "s2",
                "P1 is planned, not out: nothing to claim")
        ok("piece", BETA, "P1", "--status", "out", "--session", "s1")
        refused("P1", "--claim", "--status", "out", "--session", "s2",
                "--claim keeps the status: drop --status")
        refused("P1", "--claim", "--claim needs a session id")
        refused("new", "--title", "Another", *ROUTE, "--claim",
                "--session", "s2", "--claim takes over a piece out")
    end

    def test_a_kept_piece_taken_out_gets_its_route
        add("--status", "kept: later")
        ok("piece", BETA, "P1", "--status", "out", *ROUTE, "--session", "s1")
        assert_equal %w[out sonnet s1],
                     row.values_at(:status, :model, :claimed_by)
    end

    def test_verified_needs_a_verifier_other_than_its_route
        add
        refused("P1", "--status", "verified", "--evidence", "ran",
                "--status verified needs --verified-by")
        refused("P1", "--status", "verified", "--evidence", "ran",
                "--verified-by", "sonnet, effort: medium",
                "P1 is verified by its own route")
        ok("piece", BETA, "P1", "--status", "verified", "--evidence", "ran",
           "--verified-by", "me")
        assert_equal "me", row[:verified_by]
    end

    def test_a_dry_run_writes_nothing
        before = state
        out = ok("piece", BETA, *NEW, *ROUTE, "--dry-run")
        assert_equal "P1", out.lines.first.chomp
        assert_includes out, "dry run: nothing written"
        assert_equal before, state
    end

    # A failure naming P10 is not P1's: own matches whole ids.
    def test_a_failure_of_p10_does_not_refuse_an_edit_of_p1
        add
        Ledger::Write.run(@journal, BETA, "piece", []) do |change|
            piece(change, n: 10, title: "O13 D1")
        end
        ok("piece", BETA, "P1", "--plan", "do it")
        assert_equal "do it", row[:plan]
    end
end

# `piece --status planned --cause`: a piece out or back that goes back
# to planned says why, in a piece_returns row of the write's event,
# shown by `show` and reverted by undo and restore.
class PieceReturnTest < PieceCase
    CAUSES = "one of brief, split, depth, contract or env"
    NO_RETURN = "--cause is for a return: --status planned on a piece " \
                "out or back"

    def setup
        super
        add
        ok("piece", BETA, "P1", "--status", "out", "--session", "s1")
    end

    def back(cause = "env")
        ok("piece", BETA, "P1", "--status", "planned", "--cause", cause)
    end

    def returns = db[:piece_returns].order(:id).all
    def last_event = db[:events].order(:id).last

    def test_a_return_from_out_or_back_records_its_cause
        back("depth")
        ok("piece", BETA, "P1", "--status", "back")
        back("brief")
        causes = returns.map { it.values_at(:from_status, :cause) }
        assert_equal [%w[out depth], %w[back brief]], causes
        assert_equal ["planned", nil], row.values_at(:status, :claimed_by)
    end

    def test_a_return_is_a_row_of_its_write_event
        back
        assert_equal [last_event[:id], @beta, row[:id]],
                     returns.last.values_at(:event_id, :ledger_id, :piece_id)
    end

    def test_a_return_without_a_cause_is_refused
        refused("P1", "--status", "planned",
                "P1 goes back to planned from out: --cause says why, " \
                "#{CAUSES}")
        refused("P1", "--status", "planned", "--cause", "",
                "--cause says why")
        refused("P1", "--status", "planned", "--cause", "luck",
                "--cause luck: #{CAUSES}")
    end

    def test_a_cause_on_any_other_change_is_refused
        refused(*NEW, *ROUTE, "--cause", "env", NO_RETURN)
        refused("P1", "--status", "back", "--cause", "env", NO_RETURN)
        refused("P1", "--plan", "x", "--cause", "env", NO_RETURN)
        back
        refused("P1", "--status", "planned", "--cause", "env", NO_RETURN)
    end

    def test_show_lists_the_returns_and_the_line_stays
        back("split")
        at = Ledger::Render::Json.time(last_event[:at])
        text = ok("show", BETA, "P1")
        assert_includes text, "\nreturn: split, from out, #{at}\n"
        assert_includes text, "line: - P1 [planned] sonnet, effort: medium " \
                              "— Build the parser\n"
        item = JSON.parse(ok("show", BETA, "P1", "--json"))["item"]
        assert_equal [{ "cause" => "split", "from" => "out", "at" => at,
                        "actor" => "cli" }], item["returns"]
    end

    def test_undo_of_the_return_removes_its_row
        back
        ok("undo", BETA)
        assert_empty returns
        assert_equal "out", row[:status]
    end

    def test_restore_to_before_the_return_removes_its_row
        mark = last_event[:id]
        back
        ok("piece", BETA, "P1", "--plan", "again")
        ok("restore", BETA, "--to", "E#{mark}")
        assert_empty returns
        assert_equal "out", row[:status]
    end
end
