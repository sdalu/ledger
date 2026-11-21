# frozen_string_literal: true

require_relative "helper"

# `fact`: the id first, the line, the status line last.
class FactTest < CommandCase
    def test_a_fact_is_split_at_its_first_pointer
        out = ok("fact", BETA, "port 80 — is open — ss output")
        assert_equal ["F1", "- F1: port 80 — is open — ss output"],
                     out.lines(chomp: true)[0..1]
        assert_match(/\AStatus \(Build the thing\) — /, out.lines.last)
        assert_equal ["port 80", "is open — ss output"],
                     db[:facts].select_map(%i[text pointer]).first
    end

    def test_a_dry_run_prints_the_id_and_the_diff_and_writes_nothing
        before = state
        out = ok("fact", BETA, "a — b", "--dry-run")
        assert_equal "F1", out.lines.first.chomp
        assert_includes out, "+- F1: a — b"
        assert_includes out, "dry run: nothing written"
        assert_equal before, state
    end

    def test_ids_are_never_reused
        ok("fact", BETA, "a — b")
        assert_equal "F2", ok("fact", BETA, "c — d").lines.first.chomp
    end

    def test_a_fact_without_a_pointer_is_refused
        assert_refused("fact", BETA, "no pointer",
                       "a fact ends with — and where it was found")
        assert_refused("fact", BETA, "text — ",
                       "a fact ends with — and where it was found")
        assert_refused("fact", BETA, "two\nlines — x", "a fact ends with")
    end
end
