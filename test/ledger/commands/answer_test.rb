# frozen_string_literal: true

require_relative "helper"

# `answer`: the user's answer filed as a decision by user, its X id
# first, the question closed with its answers edge, entries taken in
# the same event.
class AnswerTest < CommandCase
    DATE = ["--date", "2026-11-20"].freeze

    def setup
        super
        ok("ask", BETA, "Which palette wins?", "--title", "Palette choice",
           "--problem", "colours clash", "--risk", "2/10 — a redraw",
           "--no-picture", "words alone")
    end

    def entry(n, ref = "O1")
        Ledger::Write.run(@journal, BETA, "inbox", []) do |change|
            change.insert(:inbox_entries, n:, at: "2026-11-20 10:00:00",
                                          ref:, payload: "{}")
        end
    end

    def test_an_answer_is_filed_and_the_question_closed
        out = ok("answer", BETA, "O1", "--decision", "the warm one", *DATE)
        assert_equal ["X1", "- 2026-11-20 — O1: the warm one — by user"],
                     out.lines(chomp: true)[0..1]
        refute_includes markdown, "- O1:"
        refute_nil db[:questions].get(:closed_at)
    end

    def test_the_decision_answers_the_question
        ok("answer", BETA, "O1", "--decision", "the warm one", *DATE)
        assert_equal "O1", db[:decisions].get(:subject)
        assert_equal %w[answers X O],
                     db[:links].first.values_at(:kind, :from_kind, :to_kind)
    end

    def test_take_marks_the_entries_in_the_same_event
        entry(1)
        entry(2)
        out = ok("answer", BETA, "O1", "--decision", "O1: warm", "--take",
                 "N1", *DATE)
        assert_includes out, "taken: N1; pending: N2"
        event = db[:events].order(:id).last
        assert_equal "answer", event[:command]
        assert_equal event[:id], db[:inbox_entries].where(n: 1).get(:taken_id)
    end

    def test_replaces_writes_the_x_to_x_edge
        ok("decide", BETA, "cold first", "--by", "me", *DATE)
        ok("answer", BETA, "O1", "--decision", "warm", "--replaces", "X1",
           *DATE)
        assert_equal %w[answers replaces],
                     db[:links].order(:id).select_map(:kind)
        assert_refused("answer", BETA, "O1", "--decision", "x", "--replaces",
                       "F1", "O1 is not asked under Open")
    end

    def test_replaces_takes_an_x_id
        assert_refused("answer", BETA, "O1", "--decision", "x", "--replaces",
                       "F1", "--replaces takes an X id, not F1")
        assert_refused("answer", BETA, "O1", "--decision", "x", "--replaces",
                       "X4", "X4 is not this ledger's")
    end

    def test_only_an_open_question_is_answered
        assert_refused("answer", BETA, "O7", "--decision", "x",
                       "O7 is not asked under Open in #{BETA}")
        assert_refused("answer", BETA, "P1", "--decision", "x",
                       "P1 is not asked under Open")
    end

    def test_an_empty_decision_is_refused
        assert_refused("answer", BETA, "O1", "--decision", " ",
                       "--decision is empty; quote the user")
        assert_refused("answer", BETA, "O1", "--decision is required")
    end

    def test_unknown_and_taken_entries_are_refused
        assert_refused("answer", BETA, "O1", "--decision", "x", "--take",
                       "N3,N4", "no inbox entry N3, N4")
        entry(1)
        ok("answer", BETA, "O1", "--decision", "x", "--take", "N1")
        ok("ask", BETA, "Which font wins?", "--title", "Font choice",
           "--problem", "fonts clash", "--risk", "2/10 — a redraw",
           "--no-picture", "words alone")
        assert_refused("answer", BETA, "O2", "--decision", "y", "--take",
                       "N1", "N1 was already taken at ")
    end

    def test_a_bad_date_is_not_a_decision_line
        assert_refused("answer", BETA, "O1", "--decision", "x", "--date",
                       "20/11/2026", "not a decision line")
    end

    def test_a_dry_run_writes_nothing
        entry(1)
        before = state
        out = ok("answer", BETA, "O1", "--decision", "x", "--take", "N1",
                 "--dry-run")
        assert_equal "X1", out.lines.first.chomp
        refute_includes out, "taken:"
        assert_equal before, state
    end
end
