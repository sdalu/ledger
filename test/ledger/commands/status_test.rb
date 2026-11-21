# frozen_string_literal: true

require "json"

require_relative "helper"

# `status`: the status line, or its parts as JSON v1.
class StatusTest < CommandCase
    def test_the_line_is_printed
        assert_equal "Status (Build the thing) — criteria 0/1 · " \
                     "pieces 0/0 verified\n",
                     ok("status", BETA)
    end

    # The title ahead of the counts leaves the close proposal read.
    def test_a_finished_ledger_proposes_to_close
        ok("criterion", BETA, "D1", "--text", "tests pass")
        ok("criterion", BETA, "D1", "--met", "ran it")
        doc = JSON.parse(ok("status", "--json", BETA))
        assert_equal "Status (Build the thing) — criteria 1/1 · pieces 0/0 " \
                     "verified · done: propose close", doc["line"]
        assert doc["propose_close"]
    end

    def test_json_carries_the_parts
        doc = JSON.parse(ok("status", "--json", BETA))
        assert_equal [1, "status", [0, 1], false],
                     doc.values_at("schema", "kind", "criteria",
                                   "propose_close")
        assert_equal({ "verified" => 0, "live" => 0, "kept" => 0 },
                     doc["pieces"])
        keys = %w[out back blocked deferred stalled unsent waiting preparing
                  words from_viewer]

        assert_equal keys, doc.keys & keys
    end

    def test_json_names_each_deferred_piece_with_its_condition
        ok("piece", BETA, "new", "--title", "Judge the practices", "--route",
           "opus, effort: high", "--status", "deferred", "--until",
           "three closures")
        doc = JSON.parse(ok("status", "--json", BETA))

        assert_equal [{ "piece" => "P1", "until" => "three closures" }],
                     doc["deferred"]
    end

    # Planned three hours before the clock: named with its age.
    def test_json_names_each_unsent_piece_with_its_age
        ok("piece", BETA, "new", "--title", "Judge the practices", "--route",
           "opus, effort: high")
        stamp_last(Ledger::Write.now - (3 * 3_600_000))
        doc = JSON.parse(ok("status", "--json", BETA))

        assert_equal [{ "piece" => "P1", "minutes" => 180 }], doc["unsent"]
        assert_includes doc["line"], " · ready, unsent: P1 (3 h)"
    end

    def stamp_last(at)
        db[:events].where(id: db[:events].max(:id)).update(at:)
    end

    def test_a_bad_limit_is_refused_naming_the_variable
        ENV["LEDGER_READY_LIMIT"] = "soon"
        Ledger::Ready.instance_variable_set(:@limit, nil)
        assert_refused("status", BETA, "LEDGER_READY_LIMIT=soon")
    ensure
        ENV.delete("LEDGER_READY_LIMIT")
        Ledger::Ready.instance_variable_set(:@limit, nil)
    end

    def test_a_ledger_without_a_live_address_is_refused
        assert_refused("status", "/work/nowhere/LEDGER.md",
                       "no live ledger at /work/nowhere/LEDGER.md")
    end
end
