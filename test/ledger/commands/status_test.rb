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
        assert_equal %w[out back blocked stalled waiting preparing words
                        from_viewer],
                     doc.keys & %w[out back blocked stalled waiting preparing
                                   words from_viewer]
    end

    def test_a_ledger_without_a_live_address_is_refused
        assert_refused("status", "/work/nowhere/LEDGER.md",
                       "no live ledger at /work/nowhere/LEDGER.md")
    end
end
