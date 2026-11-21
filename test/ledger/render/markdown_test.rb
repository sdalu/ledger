# frozen_string_literal: true

require_relative "helper"

# The whole ledger: the format line, the sections in order, the blank
# lines between blocks and the Goal blocks.
class MarkdownTest < RenderTest
    EMPTY = <<~MD
        # Ledger (format 2)

        Goal G1 (2026-11-19, verbatim):
        > the user's words

        Done when:

        Constraints (verbatim, where said):

        Facts:

        Decisions:

        Pieces:

        Open:

        Out of scope, noticed:
    MD

    FULL_GOAL = { title: "A title", short: "In a few words",
                  context: "Where it comes from",
                  quote: "first line\n\nthird line" }.freeze

    def test_r1_format_line_and_r4_labels_of_an_otherwise_empty_ledger
        assert_equal(EMPTY, text { goal(it) })
    end

    def test_r2_one_blank_line_between_blocks_and_one_final_newline
        out = text { goal(it) }

        refute_includes out, "\n\n\n"
        assert out.end_with?("noticed:\n")
        refute out.end_with?("\n\n")
    end

    def test_goal_block_with_title_short_context_and_quote
        out = text { goal(it, **FULL_GOAL) }

        assert_equal <<~MD.chomp, out.lines[2..8].join.chomp
            Goal G1 (2026-11-19, verbatim):
            Title: A title
            In short: In a few words
            Context: Where it comes from
            > first line
            >
            > third line
        MD
    end

    def test_a_done_goal_block_says_done_under_its_in_short
        out = text do |change|
            goal(change, **FULL_GOAL, done_at: 1, done_evidence: "it ships")
        end

        assert_equal ["In short: In a few words", "Done: it ships",
                      "Context: Where it comes from"],
                     out.lines(chomp: true)[4..6]
    end

    def test_a_done_goal_needs_its_evidence
        assert_raises(Sequel::CheckConstraintViolation) do
            text { goal(it, done_at: 1) }
        end
        assert_raises(Sequel::CheckConstraintViolation) do
            text { goal(it, done_at: 1, done_evidence: "") }
        end
    end

    def test_r9_quote_lines_always_carry_the_quote_mark_and_a_space
        out = text { goal(it, quote: "x\n  indented") }

        assert_includes out, "\n> x\n>   indented\n"
    end

    def test_a_stamp_is_stored_without_its_parentheses
        assert_raises(Sequel::CheckConstraintViolation) do
            text { goal(it, stamp: "(2026-11-19, verbatim)") }
        end
    end

    def test_a_revised_goal_block_follows_the_first_one
        out = text do |change|
            goal(change, title: "One")
            goal(change, stamp: "2026-11-20, revised, verbatim",
                         revised: true, title: "Two", quote: "again")
        end

        assert_includes out, "Title: One\n> the user's words\n\n" \
                             "Goal G2 (2026-11-20, revised, verbatim):\n" \
                             "Title: Two\n> again\n\nDone when:"
    end

    def test_sections_come_in_the_order_of_the_file
        labels = text { goal(it) }.lines.grep(/:$/).map(&:chomp)

        assert_equal ["Goal G1 (2026-11-19, verbatim):", "Done when:",
                      "Constraints (verbatim, where said):", "Facts:",
                      "Decisions:", "Pieces:", "Open:",
                      "Out of scope, noticed:"], labels
    end

    def test_noticed_lines_are_printed_verbatim
        out = text do |change|
            goal(change)
            change.insert(:noticed, line: "- the first thing")
            change.insert(:noticed, line: "- the second thing")
        end

        assert out.end_with?("noticed:\n- the first thing\n" \
                             "- the second thing\n")
    end

    def test_a_closed_question_is_not_under_open
        out = text do |change|
            goal(change)
            question(change)
            question(change, closed_at: 1)
        end

        assert_includes out, "Open:\n- O1: Title 1: What now?\n\nOut of"
    end

    def test_a_no_break_space_passes_through_unchanged
        title = "Cache policy"
        out = text { |change| piece(change, title:) }

        assert_includes out, "] sonnet, effort: low — Cache\u202Fpolicy\n"
    end
end
