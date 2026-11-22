# frozen_string_literal: true

require_relative "ask_test"

# `ask PATH O<n> --by P<n>|none` and the question-loop refusal: a question
# is not asked by a piece that awaits the user's word.
class AskByTest < AskCase
    def piece_awaiting(*words)
        ok("piece", BETA, "new", "--title", "Build the panel", "--route",
           "sonnet, effort: low", "--problem", "the panel is not built",
           "--risk", "2/10 — a redo", "--awaits", words.join(", "))
    end

    def asked_by(by = "P1") = ask("--no-picture", "x", "--by", by)

    def test_a_question_asked_by_a_piece_awaiting_start_is_refused
        piece_awaiting("start")

        assert_refused("ask", BETA, *QUESTION, "--no-picture", "x", "--by",
                       "P1", "O1 waits on P1, which waits on your start: " \
                             "clear the link with ledger ask PATH O1 --by " \
                             "none, or give P1 its word")
    end

    def test_a_piece_given_the_awaiting_after_the_question_is_refused
        ok("piece", BETA, "new", "--title", "Build the panel", "--route",
           "sonnet, effort: low")
        asked_by
        assert_refused("piece", BETA, "P1", "--awaits", "start", "--problem",
                       "not built", "--risk", "2/10 — a redo", "question-loop")
    end

    def test_by_none_clears_the_link_and_undo_restores_it
        ok("piece", BETA, "new", "--title", "Build the panel", "--route",
           "sonnet, effort: low")
        asked_by
        out = ok("ask", BETA, "O1", "--by", "none")
        assert_equal "O1", out.lines.first.chomp
        assert_nil question[:by_id]
        ok("undo", BETA)
        refute_nil question[:by_id]
    end

    def test_by_sets_or_changes_a_link
        2.times do
            ok("piece", BETA, "new", "--title", "Build the panel",
               "--route", "sonnet, effort: low")
        end
        ask("--no-picture", "x")
        ok("ask", BETA, "O1", "--by", "P2")
        assert_equal db[:pieces].where(n: 2).get(:id), question[:by_id]
    end

    def test_relinking_refusals
        ask("--no-picture", "x")
        assert_refused("ask", BETA, "O1", "O1 is changed by --by")
        assert_refused("ask", BETA, "O1", "--by", "none", "--title", "T",
                       "takes only --by")
        assert_refused("ask", BETA, "O9", "--by", "none", "not this ledger's")
        assert_refused("ask", BETA, *QUESTION, "--no-picture", "x", "--by",
                       "none", "clears an existing question")
    end
end
