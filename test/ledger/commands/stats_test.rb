# frozen_string_literal: true

require "json"

require_relative "helper"

# `stats`: a track record per route on BETA, built with the commands,
# each event's time set by hand (minutes from zero). Two opus pieces
# verified, P1 after a return with a cause, P2 at the first pass; P3
# blocked once; P4 under a peer goes back to planned with no
# piece_returns row (a return from before migration 002); P5 kept.
class StatsCase < CommandCase
    NEW = ["new", "--title", "Build the parser", "--route",
           "opus, effort: high"].freeze
    DONE = ["--status", "verified", "--verified-by", "me",
            "--evidence", "tests pass"].freeze
    OUT = ["--status", "out", "--session", "s1"].freeze

    def setup
        super
        @session = ENV.delete("CLAUDE_CODE_SESSION_ID")
        5.times { ok("piece", BETA, *NEW) }
        returned
        first_pass
        ok("piece", BETA, "P3", "--status", "blocked")
        ok("piece", BETA, "P3", "--status", "planned")
        unrecorded
        ok("piece", BETA, "P5", "--status", "kept: the user does it")
    end

    def teardown
        ENV.delete("CLAUDE_CODE_SESSION_ID")
        ENV["CLAUDE_CODE_SESSION_ID"] = @session if @session
        super
    end

    # P1: out 10 minutes, back to planned for depth, out 30, verified.
    def returned
        at(0, "P1", *OUT)
        at(10, "P1", "--status", "planned", "--cause", "depth")
        at(20, "P1", *OUT)
        at(50, "P1", "--status", "back")
        at(60, "P1", *DONE)
    end

    # P2: out 5 minutes, verified.
    def first_pass
        at(0, "P2", *OUT)
        at(5, "P2", *DONE)
    end

    # P4: under a peer, out 20 minutes, then planned by a write that
    # records no cause.
    def unrecorded
        ok("piece", BETA, "P4", "--route", "peer: web")
        at(100, "P4", *OUT)
        id = db[:pieces].where(ledger_id: @beta, n: 4).get(:id)
        Ledger::Write.run(@journal, BETA, "piece", []) do |change|
            change.update(:pieces, id, status: "planned", claimed_by: nil)
        end
        stamp(120)
    end

    def at(minute, *argv)
        ok("piece", BETA, *argv)
        stamp(minute)
    end

    def stamp(minute)
        db[:events].where(id: db[:events].max(:id))
                   .update(at: minute * 60_000)
    end

    def groups(*argv)
        document = JSON.parse(ok("stats", *argv, "--json"),
                              symbolize_names: true)
        assert_equal [1, "stats"], document.values_at(:schema, :kind)
        document[:groups].to_h { [it[:route], it.except(:route)] }
    end
end

# `stats` on the fixture: each column, the table, the ledgers it reads
# and that it writes nothing.
class StatsTest < StatsCase
    SONNET = "sonnet, effort: low"
    TABLE = [["route", "pieces", "first-pass", "blocked", "unsent",
              "out, median", "returns"],
             ["opus, effort: high", "3", "1/2 50%", "1 33%", "0", "10.0 min",
              "depth 1"],
             ["peer: web", "1", "-", "0 0%", "1", "20.0 min", "unrecorded 1"],
             ["kept", "1", "-", "0 0%", "0", "-", "-"]].freeze

    def test_each_group_and_its_columns_as_json
        assert_equal({ pieces: 3, first_pass_verified: 0.5,
                       blocked_share: 1.fdiv(3), median_out_minutes: 10.0,
                       returns: { depth: 1 } }, columns["opus, effort: high"])
        assert_equal({ pieces: 1, first_pass_verified: nil,
                       blocked_share: 0.0, median_out_minutes: 20.0,
                       returns: { unrecorded: 1 } }, columns["peer: web"])
        assert_equal({ pieces: 1, first_pass_verified: nil,
                       blocked_share: 0.0, median_out_minutes: nil,
                       returns: {} }, columns["kept"])
    end

    # P4, planned again at minute 120, has been ready for ages; P3,
    # planned again by a write left at its own time, has not.
    def test_the_unsent_pieces_per_route_as_json
        unsent = groups.values.map { it[:unsent] }
        assert_equal [0, 1, 0], unsent
    end

    def columns = groups.transform_values { it.except(:unsent) }

    # On a fixed clock: P3 planned again at minute 30, P4 at 120.
    def test_the_pieces_unsent_per_route_on_a_fixed_clock
        stamp_piece(3, 30)
        assert_equal [0, 0, 0], unsent_at(140)
        assert_equal [1, 0, 0], unsent_at(200)
        assert_equal [1, 1, 0], unsent_at(241)
    end

    def test_the_table_one_row_a_group_in_columns
        lines = ok("stats", BETA).lines(chomp: true)
        assert_equal(TABLE, lines.map { it.split(/ {2,}/) })
        assert_equal(["pieces", "     3", "     1", "     1"],
                     lines.map { it[20, 6] })
        assert_equal(["blocked", "1 33%", "0 0%", "0 0%"],
                     lines.map { it[40, 7].rstrip })
    end

    def test_a_piece_still_out_counts_no_span
        at(200, "P3", *OUT)
        assert_in_delta 10.0,
                        groups(BETA)["opus, effort: high"][:median_out_minutes]
    end

    def test_every_ledger_or_one
        write { piece(it) }
        assert_includes groups.keys, SONNET
        refute_includes groups(BETA).keys, SONNET
    end

    def test_a_closed_ledger_by_its_id_and_the_refusals
        write { piece(it) }
        db[:ledgers].where(id: @ledger[:id]).update(closed_at: 1)
        assert_equal [SONNET], groups("L#{@ledger[:id]}").keys
        assert_refused("stats", ADDRESS, "no live ledger at #{ADDRESS}")
        assert_refused("stats", "L999", "no ledger L999")
    end

    def everything = [state, db[:ledgers].all, db[:piece_returns].all]

    # The unsent counts of opus, the peer and kept at MINUTE.
    def unsent_at(minute)
        groups = Ledger::Stats.read(db, [@beta], now: minute * 60_000)
        assert_equal ["opus, effort: high", "peer: web", "kept"],
                     groups.map(&:route)
        groups.map(&:unsent)
    end

    # Every event touching piece N moved to MINUTE, the later ones kept
    # after it.
    def stamp_piece(number, minute)
        id = db[:pieces].where(ledger_id: @beta, n: number).get(:id)
        events = db[:event_rows].where(tbl: "pieces", row_id: id)
                                .select_map(:event_id)
        db[:events].where(id: events).update(at: minute * 60_000)
    end

    def test_it_writes_nothing
        before = everything
        ok("stats")
        ok("stats", BETA, "--json")
        assert_equal before, everything
    end
end

# `stats` reads only the events in force: an undone claim or return
# counts nowhere, and a restore that reverts the undo brings it back.
class StatsUndoTest < StatsCase
    OPUS = "opus, effort: high"

    def setup
        super
        ok("piece", BETA, "P3", *OUT)
    end

    def opus = groups[OPUS]

    def return_env
        ok("piece", BETA, "P3", "--status", "planned", "--cause", "env")
    end

    def test_a_claim_undone_leaves_no_return_and_no_span
        ok("undo", BETA)
        assert_equal({ depth: 1 }, opus[:returns])
        assert_in_delta 10.0, opus[:median_out_minutes]
    end

    def test_a_return_with_a_cause_undone_leaves_no_return
        return_env
        ok("undo", BETA)
        assert_equal "out", db[:pieces].where(ledger_id: @beta, n: 3)
                                       .get(:status)
        assert_equal({ depth: 1 }, opus[:returns])
    end

    def test_a_restore_that_reverts_the_undo_brings_the_return_back
        return_env
        back = db[:events].max(:id)
        ok("undo", BETA)
        ok("restore", BETA, "--to", "E#{back}")
        assert_equal({ depth: 1, env: 1 }, opus[:returns])
    end
end
