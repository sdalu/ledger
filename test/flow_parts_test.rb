# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# The parts of a ledger page that carry a flow: the evidence a word rests
# on, above its buttons, and the planned pieces as a list to reorder
# beside the comma field.
class FlowPartsTest < ViewerTest
    include LedgerFixture

    ROUTE = ["--route", "sonnet, effort: low"].freeze

    def build_fixture
        super
        ledger("piece", "new", *ROUTE, "--title", "write the lexer")
        ledger("piece", "new", *ROUTE, "--title", "write the <parser>")
        ledger("piece", "new", *ROUTE, "--title", "fix the reorder",
               "--status", "verified", "--verified-by", "me",
               "--evidence", "suite green, **212** of 212")
        ledger("piece", "P3", "--problem", "the fix is not committed",
               "--risk", "2/10 — the fix waits", "--plan", "commit it",
               "--no-picture", "no visible change", "--awaits", "commit")
    end

    def test_the_evidence_sits_above_the_word_buttons_with_its_record_row
        card = card("p-P3")

        assert_includes card, "<strong>212</strong> of 212 · " \
                              '<a href="#piece-P3">its row in the record</a>'
        # the line, then the word's form, whose first visible part is
        # its buttons
        assert_match(Regexp.new('<p class="word-evidence">[^\n]*?</p>' \
                                '<form class="say"[^>]*>(<input [^>]*>)+' \
                                '<div class="word-choices">'), card)
    end

    def test_the_order_is_a_list_of_titles_beside_the_field
        fold = page[%r{<details class="comment-fold order-fold".*?</details>}m]
        list = fold[%r{<ol class="order-list" hidden.*?</ol>}m]

        assert list, "no order list"
        assert_equal %w[P1 P2], list.scan(/data-id="(P\d+)"/).flatten
        assert_includes list, "write the &lt;parser&gt;"
        assert_includes list, 'aria-label="Move P1 down"'
        assert_includes fold, 'name="order" value="P1, P2"'
    end

    private

    def page
        @page ||= begin
            sign_in
            https "/l/#{@lid}"
            last_response.body
        end
    end

    # The card whose id is ANCHOR, to its closing tag's start.
    def card(anchor)
        from = page.index(%(id="#{anchor}")) or flunk("no #{anchor}")
        page[from...page.index("</li>", from)]
    end
end
