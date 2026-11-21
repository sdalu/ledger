# frozen_string_literal: true

require "json"

require_relative "helper"

# `survey`: the live ledgers at a directory or under it with their status
# and pending entries, the pieces routed to a peer, and nothing written.
class SurveyTest < CommandCase
    NESTED = "/work/beta/.claude/LEDGER.md"
    OTHER = "/work/other/LEDGER.md"
    NOW = Time.new(2026, 11, 21, 8, 0, 0)

    def setup
        super
        @session = ENV.delete("CLAUDE_CODE_SESSION_ID")
        ok("new", NESTED, *GOAL)
        ok("new", OTHER, *GOAL)
        route(BETA, "peer: Ledger")
        route(OTHER, "peer: Ledger")
        route(NESTED, "peer: ledger")
    end

    def teardown
        ENV["CLAUDE_CODE_SESSION_ID"] = @session if @session
        super
    end

    def route(path, route)
        ok("piece", path, "new", "--title", "Build the parser", "--route",
           route)
    end

    def send_entry(path, text)
        Ledger::Inbox.append(@journal, path, [{ "text" => text }],
                             actor: "cli", now: NOW)
    end

    def peek(path) = ok("check", "--peek", path).lines.last

    def test_the_ledgers_under_a_directory_with_status_and_entries
        send_entry(NESTED, "hello")
        out = ok("survey", "/work/beta")
        assert_equal "#{BETA}\n#{peek(BETA)}\n#{NESTED}\n#{peek(NESTED)}" \
                     "N1 (2026-11-21 08:00:00, note):\n    hello\n", out
    end

    def test_a_directory_with_no_ledger_says_so
        assert_equal "survey: no live ledger at or under /nowhere\n",
                     ok("survey", "/nowhere")
    end

    def test_a_peer_lists_its_pieces_across_the_journal
        out = ok("survey", "/work/beta", "--peer", "Ledger")
        lines = out.lines(chomp: true)
        assert_includes lines, "pieces routed peer: Ledger:"
        assert_includes lines, "#{BETA}  - P1 [planned] peer: Ledger — " \
                               "Build the parser"
        assert_includes lines, "#{OTHER}  - P1 [planned] peer: Ledger — " \
                               "Build the parser"
        refute(lines.any? { it.start_with?(NESTED) && it.include?("P1 [") })
    end

    def test_a_peer_with_no_piece_says_so
        out = ok("survey", "/work/beta", "--peer", "Nobody")
        assert_includes out, "peer: no piece routed peer: Nobody\n"
    end

    def survey_json(*argv)
        JSON.parse(ok("survey", "/work/beta", *argv, "--json"))
    end

    def test_json_is_one_object
        send_entry(BETA, "hello")
        doc = survey_json
        assert_equal [1, "survey"], doc.values_at("schema", "kind")
        assert_equal([BETA, NESTED], doc["ledgers"].map { it["address"] })
        assert_equal(["N1"], doc["ledgers"].first["inbox"].map { it["id"] })
        assert_nil doc["peer"]
    end

    def test_json_carries_the_peer_pieces
        pieces = survey_json("--peer", "Ledger")["peer"]["pieces"]
        assert_equal([BETA, OTHER], pieces.map { it["ledger"] })
    end

    def test_a_survey_writes_nothing_and_counts_no_beat
        ok("check", BETA)
        ok("check", BETA)
        send_entry(BETA, "hello")
        before = state_of_beats
        ok("survey", "/work", "--peer", "Ledger")
        ok("survey", "/work", "--json")
        assert_equal before, state_of_beats
    end

    def state_of_beats
        [db[:events].select_map(:id),
         db[:ledgers].select_map(%i[id beat_line beat_count])]
    end
end
