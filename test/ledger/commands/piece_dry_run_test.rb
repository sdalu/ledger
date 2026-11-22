# frozen_string_literal: true

require_relative "piece_test"

# `piece PATH new --status out --dry-run`: the new piece's events are
# rolled back, so it has no touch time and is not stalled.
class PieceDryRunTest < PieceCase
    def test_a_new_piece_set_out_in_a_dry_run_exits_zero
        out = ok("piece", BETA, *NEW, *ROUTE, "--status", "out", "--session",
                 "s1", "--dry-run")
        assert_includes out, "dry run: nothing written"
        assert_equal 0, db[:pieces].where(ledger_id: @beta).count
    end
end
