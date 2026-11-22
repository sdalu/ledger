# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# A piece's ties, one line under its head: P2 after P1, P3 obsoleted by
# P4. Each part is labelled in words, holds id chips that link to their
# cards and carry a tooltip, and is left out when empty.
class TiesTest < ViewerTest
    include LedgerFixture

    ROUTE = ["--route", "sonnet, effort: low"].freeze

    def build_fixture
        super
        ledger("piece", "new", *ROUTE, "--title", "write the lexer")
        ledger("piece", "new", *ROUTE, "--title", "write the parser",
               "--after", "P1")
        ledger("piece", "new", *ROUTE, "--title", "write the old tables")
        ledger("piece", "new", *ROUTE, "--title", "write the tables")
        ledger("piece", "P3", "--status", "obsolete", "--obsoleted-by", "P4")
    end

    def page
        @page ||= begin
            sign_in
            https "/l/#{@lid}"
            last_response.body
        end
    end

    def card(anchor)
        from = page.index(%(id="#{anchor}")) or flunk("no #{anchor}")
        page[from...page.index("</li>", from)]
    end

    def ties(anchor) = card(anchor)[%r{<p class="ties">.*?</p>}m].to_s

    # The part of a line labelled LABEL, linking to ID.
    def part(label, id) = %r{#{label}</span> <a [^>]*href="#piece-#{id}"}

    def test_a_piece_names_the_pieces_it_waits_for_and_those_waiting_on_it
        waits = ties("piece-P2")
        assert_match part("waits for", "P1"), waits
        refute_includes waits, "needed by"
        needed = ties("piece-P1")
        assert_match part("needed by", "P2"), needed
        refute_includes needed, "waits for"
    end

    def test_a_chip_carries_the_title_of_its_piece_on_hover
        line = ties("piece-P2")
        assert_match(/href="#piece-P1"[^>]*aria-describedby/, line)
        assert_includes line, ">write the lexer · planned</span>"
    end

    def test_a_piece_and_its_successor_name_each_other
        assert_match part("obsoleted by", "P4"), ties("piece-P3")
        assert_match part("obsoletes", "P3"), ties("piece-P4")
    end

    def test_an_obsolete_row_carries_its_successor_beside_its_status
        head = card("piece-P3")[%r{\A.*?</span>(?=<div class="meta"|<p)}m]
        assert_match(/obsolete.*class="succ".*href="#piece-P4"/m, head)
    end

    def test_an_unsettled_wait_says_its_status_and_the_piece_is_not_ready
        refute_includes ties("piece-P2"), "ready"
        assert_includes ties("piece-P2"), " · planned</span>"
    end

    def test_a_ready_piece_leads_with_ready_and_its_settled_wait_is_muted
        ledger("piece", "new", *ROUTE, "--title", "write the spec",
               "--status", "verified", "--verified-by", "me",
               "--evidence", "it reads")
        ledger("piece", "new", *ROUTE, "--title", "write the manual",
               "--after", "P5")
        line = ties("piece-P6")
        assert_includes line, '<span class="tie-ready">ready —</span>'
        assert_match(/class="id-link is-done" href="#piece-P5"/, line)
        assert_includes line, "· settled</span>"
    end

    def test_a_piece_without_ties_has_no_line
        ledger("piece", "new", *ROUTE, "--title", "write the docs")
        @page = nil
        assert_equal "", ties("piece-P5")
    end
end
