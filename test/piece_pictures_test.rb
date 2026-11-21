# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# A piece awaiting the user's word, under Waiting on you: its before and
# after drawn side by side, before left, or its reason for none.
class PiecePicturesTest < ViewerTest
    include LedgerFixture

    PIECE = ["new", "--title", "Fix the reorder", "--route",
             "sonnet, effort: low", "--status", "verified",
             "--verified-by", "me", "--evidence", "suite green",
             "--problem", "the fix is not committed",
             "--risk", "2/10 — the fix waits"].freeze

    def card
        sign_in
        https "/l/#{@lid}"
        last_response.body[%r{<li[^>]* id="p-P1".*?</li>}m]
    end

    def side(role)
        file = File.join(@dir, "#{role}.svg")
        File.write(file, "<svg/>")
        ledger("mockup", file, "--piece", "P1", "--#{role}")
    end

    # P1 with both sides placed, awaiting commit and push: its card.
    def paired_card
        ledger("piece", *PIECE)
        side("before")
        side("after")
        ledger("piece", "P1", "--awaits", "commit, push")
        card
    end

    def test_the_pair_is_drawn_before_left_after_right
        html = paired_card

        assert_includes html, %(<figure class="mock-tile is-pair">)
        assert_equal %w[Before After],
                     html.scan(%r{<span class="side-name">(\w+)</span>})
                         .flatten
        assert_operator html.index("/before.svg"), :<,
                        html.index("/after.svg")
        refute_includes html, "no picture:"
    end

    def test_a_reason_is_a_muted_line
        ledger("piece", *PIECE, "--awaits", "commit",
               "--no-picture", "a <wording> change")
        html = card

        assert_includes html, %(<p class="no-picture">no picture: a ) +
                              %(&lt;wording&gt; change</p>)
        refute_includes html, "mock-tile"
    end
end
