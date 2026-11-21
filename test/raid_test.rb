# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# The RAID fixture over gamma (O1 open): D2, P1 serving it, P2 after P1
# rated 7/10, P3 verified, a fact F1, A1 open (resting on F1, under P2
# and O1), A2 confirmed by F1 (under P3), a decision by me resting on F1,
# a noticed line; and the page's parts the tests read.
module RaidFixture
    include LedgerFixture

    ROUTE = ["--route", "sonnet, effort: low"].freeze

    def build_fixture
        super
        pieces
        ledger("fact", "gcc 14 is on the CI — ci.yml:4")
        ledger("assume", "the grammar is LL(1) — parse the spec's samples",
               "--see", "F1", "--for", "P2,O1")
        ledger("assume", "C23 compilers are at hand — build on the CI",
               "--for", "P3")
        ledger("assume", "A2", "--confirmed-by", "F1")
        records
    end

    def records
        ledger("decide", "build with gcc only", "--by", "me",
               "--rests-on", "F1")
        ledger("noticed", "the docs are stale")
    end

    def pieces
        ledger("criterion", "new", "--text", "the parser passes its suite")
        ledger("piece", "new", *ROUTE, "--title", "write the lexer",
               "--for", "D2")
        ledger("piece", "new", *ROUTE, "--title", "write the parser",
               "--after", "P1", "--risk", "7/10 — the grammar is ambiguous")
        ledger("piece", "new", *ROUTE, "--title", "settle the API",
               "--status", "verified", "--verified-by", "me",
               "--evidence", "it builds")
    end

    # P4, out under s1 since an event two hours ago.
    def stale_piece
        at = Ledger::Write.now - (2 * 3_600_000)
        Ledger::Write.run(@journal, @ledger, "piece", [], at:) do |change|
            change.insert(:pieces, n: change.next_id("P"), status: "out",
                                   claimed_by: "s1", model: "sonnet",
                                   effort: "low", dash: false,
                                   title: "draw the tables")
        end
    end

    # A ready piece planned HOURS ago.
    def planned_piece(hours)
        at = Ledger::Write.now - (hours * 3_600_000)
        Ledger::Write.run(@journal, @ledger, "piece", [], at:) do |change|
            change.insert(:pieces, n: change.next_id("P"), status: "planned",
                                   model: "sonnet", effort: "low", dash: false,
                                   title: "draw the charts")
        end
    end

    def page
        @page ||= begin
            sign_in
            https "/l/#{@lid}"
            last_response.body
        end
    end

    # The card or row whose id is ANCHOR, to its closing tag's start.
    def card(anchor)
        from = page.index(%(id="#{anchor}")) or flunk("no #{anchor}")
        page[from...page.index("</li>", from)]
    end

    def raid(html) = html[%r{<p class="raid">.*?</p>}m].to_s

    def raid_fold
        from = page.index(%(<details class="done-fold" id="#{@lid}-raid">))
        flunk("no RAID fold") unless from
        page[from...page.index("</details>", from)]
    end
end

# Each piece and question card's RAID line: risk, assumptions, issues,
# dependencies, a part left out when empty.
class RaidLineTest < ViewerTest
    include RaidFixture

    def test_a_piece_in_flight_says_its_risk_or_that_none_is_rated
        stale_piece
        assert_includes card("piece-P4"), "no risk rated"
        assert_match(%r{raid-part risk is-high.*7/10}, card("piece-P2"))
        refute_includes card("piece-P3"), "no risk rated"
    end

    # Nothing is at stake on a planned or deferred piece before it goes
    # out: its risk not rated goes unsaid.
    def test_a_planned_or_deferred_piece_does_not_say_none_is_rated
        ledger("piece", "new", *ROUTE, "--title", "write the docs")
        ledger("piece", "P4", "--status", "deferred",
               "--until", "the parser is done")
        refute_includes card("piece-P1"), "no risk rated"
        refute_includes card("piece-P4"), "no risk rated"
    end

    def test_a_card_names_the_assumptions_it_rests_on_with_their_state
        line = raid(card("piece-P2"))
        assert_includes line, "rests on"
        assert_includes line, 'href="#raid-A1"'
        assert_includes line, "(open)"
        assert_includes raid(card("piece-P3")), "(confirmed)"
        assert_includes raid(card("q-O1")), 'href="#raid-A1"'
    end

    def test_the_dependencies_move_from_the_meta_into_the_line
        p1 = card("piece-P1")
        assert_includes raid(p1), %(serves <a href="#crit-D2")
        refute_match(/class="meta">[^<]*for /, p1)
        assert_includes raid(card("piece-P2")), "waits for"
    end

    def test_the_risk_leaves_the_facets_for_the_line
        refute_includes card("q-O1"), "facet risk"
        assert_includes raid(card("q-O1")), "5/10"
    end

    def test_a_blocked_piece_says_so_and_a_part_without_words_is_left_out
        ledger("piece", "P1", "--status", "blocked")
        line = raid(card("piece-P1"))
        assert_includes line, %(<span class="raid-part issues">blocked</span>)
        refute_includes line, "raid-part assumptions"
    end

    def test_a_stalled_piece_is_marked_on_its_card_and_in_the_side_list
        stale_piece
        assert_includes raid(card("piece-P4")), "stalled 2 h"
        assert_match(/href="#piece-P4">.*?out · stalled 2 h · with sonnet/,
                     page)
    end

    def test_a_piece_ready_past_the_limit_says_how_long_on_its_card
        planned_piece(3)
        assert_includes raid(card("piece-P4")), "ready, not sent for 3 h"
        refute_includes raid(card("piece-P1")), "not sent"
    end

    def test_a_returned_piece_names_its_causes
        ledger("piece", "P1", "--status", "out", "--session", "s1")
        ledger("piece", "P1", "--status", "planned", "--cause", "depth")
        assert_includes raid(card("piece-P1")), "returned 1: depth"
    end

    def test_a_settled_piece_on_record_carries_its_line
        assert_includes raid(card("piece-P3")), "(confirmed)"
    end
end

# The RAID line's forward parts: what waits on a piece, the question it
# prepares, the decisions behind an entry, a question's issues.
class RaidForwardTest < ViewerTest
    include RaidFixture

    def ask_by(*by)
        ledger("ask", "which tool?", "--title", "Lexer tool",
               "--problem", "two tools", "--risk", "2/10 — rework",
               *by, "--no-picture", "a choice of words")
    end

    # O1 or O2 waiting HOURS, as the journal's question row says.
    def age_questions(hours)
        at = Ledger::Write.now - (hours * 3_600_000)
        @journal.db[:events].update(at:)
        @page = nil
    end

    def test_a_piece_says_which_pieces_wait_on_it_linked_to_their_cards
        line = raid(card("piece-P1"))
        assert_includes line, 'needed by <a href="#piece-P2"'
        refute_includes raid(card("piece-P2")), "needed by"
    end

    def test_a_settled_piece_is_not_listed_as_waiting
        ledger("piece", "new", *RaidFixture::ROUTE, "--title", "done soon",
               "--after", "P3", "--status", "verified", "--verified-by", "me",
               "--evidence", "it builds")
        refute_includes raid(card("piece-P3")), "needed by"
    end

    def test_a_piece_says_the_question_it_prepares
        ask_by("--by", "P2")
        assert_includes raid(card("piece-P2")), 'prepares <a href="#q-O2"'
        refute_includes raid(card("piece-P1")), "prepares"
    end

    def test_an_entry_names_the_decisions_that_led_to_it
        ledger("decide", "split the work", "--by", "me",
               "--led-to", "P1,O1")
        assert_match(/decided in <a href="#dec-\d+"[^>]*>[^<]*X\d/,
                     raid(card("piece-P1")))
        assert_includes raid(card("q-O1")), "decided in"
        refute_includes raid(card("piece-P2")), "decided in"
    end

    def test_the_decided_link_lands_on_the_decision_row
        ledger("decide", "split the work", "--by", "me", "--led-to", "P1")
        at = raid(card("piece-P1"))[/href="#(dec-\d+)"/, 1]
        assert_includes page, %(id="#{at}")
    end

    def test_a_question_waiting_over_an_hour_says_how_long
        ask_by
        refute_includes raid(card("q-O2")), "waiting"
        age_questions(3)
        assert_includes raid(card("q-O2")), "waiting 3 h"
    end

    def test_a_question_says_its_answering_piece_is_stalled
        stale_piece
        ledger("ask", "which tool?", "--title", "Lexer tool",
               "--problem", "two tools", "--risk", "2/10 — rework",
               "--by", "P4", "--no-picture", "a choice of words")
        assert_includes raid(card("q-O2")),
                        "answered by <a href=\"#piece-P4\""
        line = raid(card("q-O2"))
        assert_includes line, ", stalled 2 h"
        assert_equal 1, line.scan("answered by").size
    end
end

# The record's RAID fold: Risks, Assumptions, Issues, Dependencies.
class RaidFoldTest < ViewerTest
    include RaidFixture

    def test_the_fold_is_titled_in_words
        assert_includes raid_fold,
                        "Risks, assumptions, issues, dependencies (8)"
        refute_includes raid_fold, ">RAID"
    end

    def test_the_fold_lists_risks_highest_first
        fold = raid_fold
        assert_operator fold.index("7/10"), :<, fold.index("5/10")
        assert_includes fold, "<h3>Risks (2)</h3>"
    end

    def test_open_assumptions_come_first_then_the_decisions_by_me
        fold = raid_fold
        a1 = fold.index('id="raid-A1"')
        assert_operator a1, :<, fold.index('id="raid-A2"')
        assert_operator fold.index('id="raid-A2"'), :<, fold.index("by me")
        assert_includes fold, "<h3>Assumptions (3)</h3>"
        assert_includes fold, "check: parse the spec&#x27;s samples"
    end

    def test_an_assumption_says_what_it_rests_on_and_its_fact
        fold = raid_fold
        assert_includes fold, "rests on: F1</div>"
        assert_match(%r{for: <a href="#piece-P2".*?</span>, <a href="#q-O1"},
                     fold)
        assert_includes fold, "by: F1</div>"
        assert_match(/build with gcc only.*?rests on: F1/m, fold)
    end

    def test_the_fold_lists_issues_and_dependencies
        stale_piece
        fold = raid_fold
        assert_includes fold, "<h3>Issues (3)</h3>"
        assert_includes fold, "stalled 2 h: draw the tables"
        assert_includes fold, "the docs are stale"
        assert_match(%r{P2</a><span[^>]*>[^<]*</span> waits for <a href=},
                     fold)
    end

    def test_a_refuted_assumption_fails_the_check
        ledger("assume", "A1", "--refuted-by", "F1")
        assert_includes raid_fold, "assumptions-refuted"
        assert_includes raid(card("piece-P2")), "(refuted)"
    end

    def test_a_deferred_condition_and_a_by_piece_are_dependencies
        ledger("piece", "P1", "--status", "deferred", "--until", "the release")
        ledger("ask", "which tool?", "--title", "Lexer tool",
               "--problem", "two tools", "--risk", "2/10 — rework",
               "--by", "P2", "--no-picture", "a choice of words")
        fold = raid_fold
        assert_match(%r{P1</a>.*? until the release}, fold)
        assert_match(%r{O2</a>.*? answered by <a href="#piece-P2"}, fold)
        assert_includes raid(card("q-O2")), "answered by"
    end
end
