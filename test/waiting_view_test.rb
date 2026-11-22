# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# What the script needs to sort and filter Waiting on you by risk: each
# card and each row of the side list carries its rating (none when the
# risk is unrated) and its place in the oldest-first order; the control
# is in the head, hidden until the script shows it.
class WaitingViewTest < ViewerTest
    include LedgerFixture

    HOUR = 3_600_000
    TITLES = ["The tool name", "The tool timing"].freeze

    # O1 (risk 8) asked two hours ago, O2 (risk 3) one: O1 leads.
    def build_fixture
        at(3) { ledger("new", *GOAL) }
        at(2) { ledger("ask", *question(1, 8)) }
        at(1) { ledger("ask", *question(2, 3)) }
    end

    def test_each_card_carries_its_rating_and_place
        cards = section.scan(/<li [^>]*data-wait-order[^>]*>/)

        assert_equal 2, cards.length
        assert_match(/id="q-O1"/, cards[0])
        assert_match(/data-risk="8" data-wait-order="0"/, cards[0])
        assert_match(/id="q-O2"/, cards[1])
        assert_match(/data-risk="3" data-wait-order="1"/, cards[1])
    end

    def test_each_row_of_the_side_list_carries_them_too
        rows = nav.scan(/<li [^>]*data-wait-order[^>]*>/)

        assert_equal 2, rows.length
        assert_match(/data-risk="8" data-wait-order="0"/, rows[0])
        assert_match(/data-risk="3" data-wait-order="1"/, rows[1])
    end

    def test_an_unrated_risk_leaves_the_rating_off
        unrate("The tool timing")

        card = section[/<li [^>]*id="q-O2"[^>]*>/]

        assert_match(/ data-wait-order="1"/, card)
        refute_match(/data-risk/, card)
    end

    def test_the_control_is_in_the_head_and_hidden
        control = head[%r{<div class="waiting-view"[^>]*>.*?</div>}m]

        assert_match(/\A<div class="waiting-view" hidden>/, control)
        assert_equal %w[oldest risk], values(control, "view-order")
        assert_equal %w[all 4 7], values(control, "view-show")
        assert_match(/Oldest wait/, control)
        assert_match(/Highest risk/, control)
        assert_match(/Risk 4\+/, control)
        assert_match(/Risk 7\+/, control)
    end

    private

    # The values of the radios named NAME in HTML.
    def values(html, name)
        html.scan(/name="#{name}" value="(\w+)"/).flatten
    end

    def page
        sign_in
        https "/l/#{@lid}"
        last_response.body
    end

    def head = page[%r{<header class="ledger-head".*?</header>}m]
    def section = page[%r{<section class="waiting".*?</section>}m]
    def nav = page[%r{<nav class="question-nav".*?</nav>}m]

    def question(number, risk)
        ["which #{number}?", "--title", TITLES.fetch(number - 1),
         "--problem", "two", "--risk", "#{risk}/10 — meh",
         "--choices", "A = one #{number} | B = two #{number}",
         "--recommend", "A, simple",
         "--no-picture", "a choice of words"]
    end

    # The question's risk, rewritten as no rating.
    def unrate(title)
        @journal.db[:questions].where(title:)
                .update(risk: "not rated", risk_rating: nil)
    end

    # The journal's clock HOURS before now while the block writes.
    def at(hours, &)
        moment = Ledger::Write.now - (hours * HOUR)
        clock = Ledger::Write.method(:now)
        Ledger::Write.define_singleton_method(:now) { moment }
        yield
    ensure
        Ledger::Write.define_singleton_method(:now, clock)
    end
end

# A ledger with nothing waiting has no order or filter to offer.
class WaitingViewEmptyTest < ViewerTest
    include LedgerFixture

    def build_fixture = ledger("new", *GOAL)

    def test_nothing_waiting_leaves_the_control_out
        sign_in
        https "/l/#{@lid}"

        refute_includes last_response.body, '<div class="waiting-view"'
    end
end
