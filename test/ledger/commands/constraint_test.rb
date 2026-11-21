# frozen_string_literal: true

require_relative "helper"

# `constraint`: the user's words and where they were said.
class ConstraintTest < CommandCase
    def test_a_constraint_is_written_with_its_quote
        out = ok("constraint", BETA, "no legacy", "--where", "turn 3")
        assert_equal ["C1", "- C1: \"no legacy\" — turn 3"],
                     out.lines(chomp: true)[0..1]
        assert_equal "no legacy", db[:constraints].get(:quote)
    end

    def test_outer_double_quotes_are_dropped
        ok("constraint", BETA, "\"no legacy\"", "--where", "turn 3")
        assert_equal "no legacy", db[:constraints].get(:quote)
    end

    def test_a_dry_run_writes_nothing
        before = state
        out = ok("constraint", BETA, "q", "--where", "w", "--dry-run")
        assert_includes out, "dry run: nothing written"
        assert_equal before, state
    end

    def test_an_empty_quote_is_refused
        assert_refused("constraint", BETA, "  ", "--where", "w",
                       "the quote is empty")
        assert_refused("constraint", BETA, "\"\"", "--where", "w",
                       "the quote is empty")
    end

    def test_an_empty_where_is_refused
        assert_refused("constraint", BETA, "q", "--where", " ",
                       "--where is empty; say where the user said it")
        assert_refused("constraint", BETA, "q",
                       "--where is empty; say where the user said it")
    end
end
