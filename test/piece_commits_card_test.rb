# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# A piece that holds commits: its card says them in one muted line, the
# ids in monospace; a piece with none says nothing.
class PieceCommitsCardTest < ViewerTest
    include LedgerFixture

    PIECE = ["new", "--title", "Fix the reorder", "--route",
             "sonnet, effort: low", "--status", "verified",
             "--verified-by", "me", "--evidence", "suite green",
             "--problem", "the fix is not pushed",
             "--risk", "2/10 — the fix waits", "--no-picture", "wording",
             "--awaits", "push"].freeze

    def card
        sign_in
        https "/l/#{@lid}"
        last_response.body[%r{<li[^>]* id="p-P1".*?</li>}m]
    end

    def test_the_commits_are_one_muted_line_of_monospace_ids
        ledger("piece", *PIECE)
        ledger("piece", "P1", "--commits", "a1b2c3d,e4f5a6b")

        assert_includes card, %(<p class="no-picture commits">Commits: ) +
                              "<code>a1b2c3d</code>, <code>e4f5a6b</code></p>"
    end

    def test_a_piece_without_commits_has_no_line
        ledger("piece", *PIECE)

        refute_includes card, "Commits:"
    end
end
