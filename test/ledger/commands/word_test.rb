# frozen_string_literal: true

require_relative "helper"

# `word`: the user's word on a piece filed as a decision by user with a
# led_to edge, the word no longer awaited, its scope gone with it.
class WordTest < CommandCase
    DATE = ["--date", "2026-11-20"].freeze

    def setup
        super
        ok("piece", BETA, "new", "--title", "Ship the parser", "--route",
           "haiku, effort: low", "--problem", "it waits", "--risk",
           "4/10 — a bad push", "--awaits", "start, other (the shots)",
           "--scope", "start = begin it | other = look at them")
    end

    def entry(n)
        Ledger::Write.run(@journal, BETA, "inbox", []) do |change|
            change.insert(:inbox_entries, n:, at: "2026-11-20 10:00:00",
                                          ref: "P1", payload: "{}")
        end
    end

    def piece = db[:pieces].where(ledger_id: @beta, n: 1).first

    def test_a_word_is_filed_and_no_longer_awaited
        out = ok("word", BETA, "P1", "--word", "start", *DATE)
        lines = out.lines(chomp: true)
        assert_equal ["X1", '- 2026-11-20 — P1: "start" — by user'],
                     lines[0..1]
        assert_includes lines[2], "— scope: other = look at them"
        assert_includes lines[2], "— awaits: other (the shots)"
        assert_equal %w[led_to X P],
                     db[:links].first.values_at(:kind, :from_kind, :to_kind)
    end

    def test_an_other_word_is_named_with_its_what
        ok("word", BETA, "P1", "--word", "start, other (the shots)", *DATE)
        assert_empty db[:piece_awaits].all
        assert_empty db[:piece_scopes].all
    end

    def test_drop_drops_the_piece
        ok("word", BETA, "P1", "--word", "drop", *DATE)
        assert_equal "dropped", piece[:status]
        assert_empty db[:piece_awaits].all
    end

    def test_taken_entries_name_the_viewer_in_the_decision
        entry(1)
        out = ok("word", BETA, "P1", "--word", "start", "--take", "N1", *DATE)
        assert_includes out, '"start" (N1, from the viewer) — by user'
        assert_includes out, "taken: N1; pending: none"
    end

    def test_the_target_is_a_piece_of_this_ledger
        assert_refused("word", BETA, "O1", "--word", "start",
                       "the target is P<n>")
        assert_refused("word", BETA, "P9", "--word", "start",
                       "no P9 under Pieces in #{BETA}")
    end

    def test_an_empty_word_is_refused
        assert_refused("word", BETA, "P1", "--word", " ", "--word is empty")
    end

    def test_only_an_awaited_word_is_given
        assert_refused("word", BETA, "P1", "--word", "commit",
                       'P1 does not await "commit" (awaits: start, other ' \
                       "(the shots))")
        ok("word", BETA, "P1", "--word", "start, other (the shots)")
        assert_refused("word", BETA, "P1", "--word", "start",
                       "P1 awaits no word")
    end

    def test_unknown_entries_are_refused
        assert_refused("word", BETA, "P1", "--word", "start", "--take", "N2",
                       "no inbox entry N2")
    end

    def test_a_bad_date_is_not_a_decision_line
        assert_refused("word", BETA, "P1", "--word", "start", "--date",
                       "20/11/2026", "not a decision line")
    end
end
