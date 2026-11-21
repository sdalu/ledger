# frozen_string_literal: true

require "json"

require_relative "helper"

# `status`: the status line, or its parts as JSON v1.
class StatusTest < CommandCase
    def test_the_line_is_printed
        assert_equal "Status — criteria 0/1 · pieces 0/0 verified\n",
                     ok("status", BETA)
    end

    def test_json_carries_the_parts
        doc = JSON.parse(ok("status", "--json", BETA))
        assert_equal [1, "status", [0, 1], false],
                     doc.values_at("schema", "kind", "criteria",
                                   "propose_close")
        assert_equal({ "verified" => 0, "live" => 0, "kept" => 0 },
                     doc["pieces"])
        keys = %w[out back blocked deferred stalled waiting preparing words
                  from_viewer]

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

    def test_a_ledger_without_a_live_address_is_refused
        assert_refused("status", "/work/nowhere/LEDGER.md",
                       "no live ledger at /work/nowhere/LEDGER.md")
    end
end
