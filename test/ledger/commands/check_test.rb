# frozen_string_literal: true

require "json"

require_relative "helper"
require "ledger/hooks/main"

# `check`: one verdict per rule, then the status line, which beats.
class CheckTest < CommandCase
    def test_every_rule_is_reported_then_the_status_line
        code, out, = cli("check", BETA)
        assert_equal 0, code
        lines = out.lines(chomp: true)
        assert_equal "ok   goal-titled", lines.first
        assert_equal "Status (Build the thing) — criteria 0/1 · " \
                     "pieces 0/0 verified", lines.last
    end

    def test_a_failing_rule_is_exit_1_with_its_detail_and_hint
        code, out, = cli("check", "--final", "--fix-hints", BETA)
        assert_equal 1, code
        assert_includes out, "FAIL final-criteria -- D1 unmarked"
        assert_includes out, "  hint: "
    end

    def test_the_status_line_beats_unless_peeked
        ok("check", BETA)
        refute_includes ok("check", "--peek", BETA), "unchanged"
        assert_includes ok("check", BETA), "· unchanged ×1"
        assert_includes ok("check", BETA), "· unchanged ×2"
    end

    def test_json_is_one_object
        doc = JSON.parse(ok("check", "--json", BETA))
        assert_equal [1, "check"], doc.values_at("schema", "kind")
        assert_equal({ "name" => "goal-titled", "ok" => true, "detail" => "" },
                     doc["reports"].first)
        assert_match(/\AStatus \(Build the thing\) — /, doc["status"])
    end
end

# Two live ledgers: each check, and the heartbeat that shows it, names
# its own ledger by its title.
class CheckTwoLedgersTest < CommandCase
    GAMMA = "/work/gamma/LEDGER.md"
    TITLES = { BETA => "Build the thing", GAMMA => "Write the docs" }.freeze

    def setup
        super
        ok("new", GAMMA, "--goal", "write the docs now", "--title",
           "Write the docs", "--short", "docs", "--date", "2026-11-20")
    end

    def test_each_check_and_its_heartbeat_name_their_ledger
        TITLES.each do |path, title|
            out = ok("check", path)
            line = "Status (#{title}) — criteria 0/1 · pieces 0/0 verified"
            assert_equal line, out.lines(chomp: true).last
            assert_equal line, heartbeat(path, out)
        end
    end

    private

    def heartbeat(path, out)
        payload = { tool_name: "Bash",
                    tool_input: { command: "bin/ledger check #{path}" },
                    tool_response: { stdout: out } }
        answer = Ledger::Hooks.answer("heartbeat", JSON.generate(payload))
        JSON.parse(answer.out)["systemMessage"]
    end
end
