# frozen_string_literal: true

require "json"

require_relative "helper"

# `piece`: once the user's word on a piece is pending in the inbox or
# given, --scope, --problem and --plan stay as they are; a new --awaits
# lifts that.
class PieceWordScopeTest < CommandCase
    DATE = ["--date", "2026-11-20"].freeze
    REFUSAL = "word-scope"

    def setup
        super
        ok("piece", BETA, "new", "--title", "Ship the parser", "--route",
           "haiku, effort: low", "--problem", "it waits", "--risk",
           "4/10 — a bad push", "--awaits", "start, other (the shots)",
           "--scope", "start = begin it | other = look at them", "--plan",
           "do it")
    end

    def piece = db[:pieces].where(ledger_id: @beta, n: 1).first

    def entry(word: "start", taken: false)
        payload = JSON.generate("word" => word)
        Ledger::Write.run(@journal, BETA, "inbox", []) do |change|
            change.insert(:inbox_entries, n: 1, at: "2026-11-20 10:00:00",
                                          ref: "P1", malformed: false,
                                          payload:)
        end
        take_entry if taken
    end

    def take_entry
        ok("take", BETA, "N1")
    end

    def pend = entry

    def give = ok("word", BETA, "P1", "--word", "start", *DATE)

    def refused(*flags)
        assert_refused("piece", BETA, "P1", *flags, REFUSAL)
    end

    def test_each_field_is_refused_under_a_pending_word
        pend
        refused("--scope", "start = begin it | other = look at them and more")
        refused("--problem", "it waits, and more")
        refused("--plan", "do it, and more")
    end

    def test_the_refusal_is_recorded_under_its_rule
        pend
        refused("--plan", "do it, and more")
        assert_equal ["word-scope"],
                     db[:outcomes].where(kind: "refusal").select_map(:rule)
    end

    def test_each_field_is_refused_under_a_given_word
        give
        refused("--scope", "other = look at them and more")
        refused("--problem", "it waits, and more")
        refused("--plan", "do it, and more")
    end

    def test_the_same_value_is_allowed
        pend
        ok("piece", BETA, "P1", "--problem", "it waits", "--plan", "do it",
           "--scope", "start = begin it | other = look at them")
    end

    def test_a_first_fill_is_allowed
        ok("piece", BETA, "P1", "--plan", "")
        pend
        ok("piece", BETA, "P1", "--plan", "do it now")
        assert_equal "do it now", piece[:plan]
    end

    def test_other_flags_are_allowed
        pend
        ok("piece", BETA, "P1", "--what", "a detail", "--status", "planned",
           "--no-picture", "no screen",
           "--commits", "abc1234", "--gate", "unit: passed (ok)")
        assert_equal "a detail", piece[:detail]
    end

    def test_fields_change_freely_without_a_word
        ok("piece", BETA, "P1", "--plan", "another plan")
        assert_equal "another plan", piece[:plan]
    end

    def test_a_taken_entry_is_no_pending_word
        entry(taken: true)
        ok("piece", BETA, "P1", "--plan", "another plan")
    end

    def test_a_new_awaits_lifts_it_in_the_same_write
        pend
        ok("piece", BETA, "P1", "--awaits", "start, other (more)", "--scope",
           "start = begin it | other = look at more", "--plan", "new plan")
        assert_equal "new plan", piece[:plan]
    end

    def test_a_new_awaits_lifts_it_after_a_given_word
        give
        refused("--plan", "late plan")
        ok("piece", BETA, "P1", "--awaits", "other (the shots), other (more)")
        ok("piece", BETA, "P1", "--plan", "late plan")
        assert_equal "late plan", piece[:plan]
    end
end
