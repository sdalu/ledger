# frozen_string_literal: true

require_relative "helper"

# `piece P<n> --no-commit WHY`: stored on the piece, shown on its line,
# cleared by ''.
class NoCommitTest < CommandCase
    def setup
        super
        ok("piece", BETA, "new", "--title", "Try the sort", "--route",
           "sonnet, effort: low")
    end

    def piece(*) = ok("piece", BETA, "P1", *)

    def test_the_reason_is_stored_and_shown_on_the_line
        out = piece("--no-commit", "an experiment")

        assert_includes out, "— no commit: an experiment"
        assert_equal "an experiment", db[:pieces].where(n: 1).get(:no_commit)
    end

    def test_an_empty_reason_clears_it
        piece("--no-commit", "an experiment")

        refute_includes piece("--no-commit", ""), "no commit"
        assert_nil db[:pieces].where(n: 1).get(:no_commit)
    end

    def test_a_piece_without_it_shows_nothing
        refute_includes piece("--plan", "sort by name"), "no commit"
    end
end
