# frozen_string_literal: true

require_relative "piece_test"

# `piece P<n> --status back --handback`: a delegate's hand-back sets a
# piece out back and says so in one line; on any other status it changes
# nothing and says the status found, exit 0; any other use is refused.
class HandbackTest < PieceCase
    def setup
        super
        add
    end

    def handback(*extra)
        cli("piece", BETA, "P1", "--status", "back", "--handback", *extra)
    end

    def test_a_piece_out_goes_back_in_one_line
        ok("piece", BETA, "P1", "--status", "out", "--session", "s1")
        code, out, err = handback

        assert_equal [0, ""], [code, err]
        assert_equal ["hand-back recorded on #{BETA} P1"],
                     out.lines(chomp: true)
        assert_equal ["back", nil], row.values_at(:status, :claimed_by)
    end

    def test_a_piece_not_out_is_left_as_it_is
        ok("piece", BETA, "P1", "--status", "verified", "--evidence", "ran",
           "--verified-by", "me")
        before = state
        code, out, = handback

        assert_equal 0, code
        assert_equal ["P1 is verified; the hand-back changes nothing"],
                     out.lines(chomp: true)
        assert_equal before, state
    end

    def test_a_planned_piece_is_not_moved_either
        _, out, = handback

        assert_equal "P1 is planned; the hand-back changes nothing\n", out
        assert_equal "planned", row[:status]
    end

    def test_another_status_is_refused
        refused("P1", "--status", "verified", "--handback",
                "--handback goes with --status back alone.")
        refused("P1", "--handback", "--handback goes with --status back")
    end

    def test_another_flag_is_refused
        refused("P1", "--status", "back", "--handback", "--evidence", "ran",
                "--handback goes with --status back alone: drop --evidence.")
        refused("P1", "--status", "back", "--handback", "--dry-run",
                "drop --dry-run.")
    end

    def test_new_and_an_unknown_piece_are_refused
        refused("new", "--status", "back", "--handback",
                "--handback needs a piece, P<n>, not new.")
        refused("P9", "--status", "back", "--handback",
                "there is no P9 under Pieces in")
    end
end
