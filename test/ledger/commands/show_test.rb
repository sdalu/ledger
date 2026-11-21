# frozen_string_literal: true

require "json"

require_relative "helper"

# `show`: the whole ledger, or one item as `key: value` lines or JSON.
class ShowTest < CommandCase
    def setup
        super
        ok("fact", BETA, "port 80 is open — ss output")
        ok("decide", BETA, "go ahead", "--by", "user", "--date", "2026-11-20",
           "--rests-on", "F1")
    end

    def test_no_id_prints_the_whole_ledger
        assert_equal markdown, ok("show", BETA)
    end

    def test_an_id_prints_its_fields
        assert_equal <<~TEXT, ok("show", BETA, "F1")
            id: F1
            text: port 80 is open
            pointer: ss output
            pointer_kind: text
            line: - F1: port 80 is open — ss output
        TEXT
    end

    def test_a_decision_shows_its_links
        out = ok("show", BETA, "X1")
        assert_includes out, "id: X1\n"
        assert_includes out, "rests-on: F1\n"
    end

    def test_json_is_a_ledger_or_an_item
        assert_equal "ledger", JSON.parse(ok("show", BETA, "--json"))["kind"]
        item = JSON.parse(ok("show", BETA, "X1", "--json"))
        assert_equal ["item", { "rests_on" => ["F1"] }],
                     [item["kind"], item["item"]["links"]]
    end

    def test_a_noticed_line_has_the_id_of_its_row
        ok("noticed", BETA, "side thing")
        id = db[:noticed].get(:id)
        assert_includes ok("show", BETA, "Z#{id}"), "line: - side thing"
    end

    def test_an_unknown_id_is_refused
        assert_refused("show", BETA, "P9", "P9 is no piece, question")
        assert_refused("show", BETA, "Z99", "Z99 is no piece, question")
        assert_refused("show", BETA, "nope", "nope is no piece, question")
    end
end
