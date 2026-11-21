# frozen_string_literal: true

require_relative "helper"

# `edit`: the words of the items that have no writer of their own.
class EditTest < CommandCase
    def setup
        super
        ok("fact", BETA, "port 80 — ss output")
        ok("constraint", BETA, "no legacy", "--where", "turn 3")
        ok("decide", BETA, "take B", "--by", "user", "--note", "n",
           "--date", "2026-11-20")
        ok("noticed", BETA, "side thing")
    end

    def test_a_fact_keeps_its_pointer
        out = ok("edit", BETA, "F1", "--text", "port 443")
        assert_equal "- F1: port 443 — ss output", out.lines.first.chomp
    end

    def test_a_constraint_is_split_again_into_its_quote
        out = ok("edit", BETA, "C1", "--text", "\"never legacy\" — turn 5")
        assert_equal "- C1: \"never legacy\" — turn 5", out.lines.first.chomp
        assert_equal "never legacy", db[:constraints].get(:quote)
    end

    def test_a_decision_keeps_its_by_date_and_note
        out = ok("edit", BETA, "X1", "--text", "O4: take C")
        assert_equal "- 2026-11-20 — O4: take C — by user (n)",
                     out.lines.first.chomp
        assert_equal "O4", db[:decisions].get(:subject)
    end

    def test_a_noticed_line_is_edited_by_its_row_id
        id = db[:noticed].get(:id)
        out = ok("edit", BETA, "Z#{id}", "--text", "other")
        assert_equal "- other\n", out.lines.first
    end

    def test_the_goal_title_is_edited
        out = ok("edit", BETA, "goal", "--text", "A newer title")
        assert_equal "Title: A newer title", out.lines.first.chomp
        assert_equal "A newer title", db[:goals].get(:title)
    end

    def test_a_dry_run_writes_nothing
        before = state
        out = ok("edit", BETA, "F1", "--text", "x", "--dry-run")
        assert_includes out, "dry run: nothing written"
        assert_equal before, state
    end

    def test_an_id_edit_does_not_take_is_refused
        assert_refused("edit", BETA, "P1", "--text", "x",
                       "P1 has its own writer: piece PATH P<n> --what")
        assert_refused("edit", BETA, "D1", "--text", "x",
                       "D1 has its own writer")
        assert_refused("edit", BETA, "W1", "--text", "x",
                       "W1 is not an item edit takes")
        assert_refused("edit", BETA, "nope", "--text", "x",
                       "nope is not an item edit takes")
    end

    def test_an_unknown_id_is_refused
        assert_refused("edit", BETA, "F9", "--text", "x",
                       "F9 is not this ledger's")
        assert_refused("edit", BETA, "Z999", "--text", "x",
                       "Z999 is not this ledger's")
    end

    def test_an_empty_text_is_refused
        assert_refused("edit", BETA, "F1", "--text", " ", "--text is empty")
        assert_refused("edit", BETA, "F1", "--text is empty")
    end

    def test_a_title_that_is_not_a_title_is_refused
        assert_refused("edit", BETA, "goal", "--text", "Why: no",
                       "the title holds `: `")
    end

    def test_a_decision_line_that_would_not_parse_is_refused
        db[:decisions].update(note: "a (b)")
        assert_refused("edit", BETA, "X1", "--text", "x", "not a decision line")
    end
end
