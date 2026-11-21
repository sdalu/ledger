# frozen_string_literal: true

require_relative "helper"

# `close`: a finished ledger leaves the live ones, its row kept.
class CloseTest < CommandCase
    def finish
        ok("criterion", BETA, "D1", "--met", "seen")
    end

    def test_an_unfinished_ledger_is_not_closed
        before = state
        code, out, err = cli("close", BETA)
        assert_equal 1, code
        assert_includes out, "FAIL final-criteria -- D1 unmarked"
        assert_includes err, "#{BETA}: not closed; --final fails"
        assert_equal before, state
        assert_nil db[:ledgers].where(id: @beta).get(:closed_at)
    end

    def test_a_pending_viewer_entry_blocks_the_close
        finish
        db[:inbox_entries].insert(ledger_id: @beta, n: 1, at: "2026-11-21",
                                  payload: "{}")
        code, out, = cli("close", BETA)
        assert_equal 1, code
        assert_includes out,
                        "FAIL inbox -- the user's entries not filed yet: N1"
        assert_nil db[:ledgers].where(id: @beta).get(:closed_at)
    end

    def test_a_closed_ledger_frees_its_address_and_carries_its_noticed_lines
        ok("noticed", BETA, "side thing")
        finish
        out = ok("close", BETA)
        assert_equal ["closed: #{BETA} (L#{@beta})", "noticed, to carry: 1",
                      "- side thing"], out.lines(chomp: true)
        refute_nil db[:ledgers].where(id: @beta).get(:closed_at)
        assert_equal 2, cli("status", BETA)[0]
        ok("new", BETA, *GOAL)
    end
end
