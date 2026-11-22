# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# After an answer the page moves on to the first card still waiting
# AFTER the answered one, in the page's order (the oldest wait first),
# wrapping to the first only when none follows: in the receipt's link
# (what the page script follows) and in the no-script redirect.
class NextWaitingTest < ViewerTest
    include LedgerFixture
    include Sends

    HOUR = 3_600_000

    # O1 asked three hours ago, O2 two, O3 one: the page's order.
    def build_fixture
        at(4) { ledger("new", *GOAL) }
        [3, 2, 1].each_with_index do |hours, number|
            at(hours) { ledger("ask", *question(number + 1)) }
        end
    end

    def test_an_answer_in_the_middle_goes_to_the_card_after_it
        sign_in
        answer("O2")

        assert_equal "/l/#{@lid}#q-O3", last_response.headers["Location"]
        assert_equal "q-O3", link("q-O2")
    end

    def test_an_answer_to_the_first_goes_to_the_second
        sign_in
        answer("O1")

        assert_equal "/l/#{@lid}#q-O2", last_response.headers["Location"]
        assert_equal "q-O2", link("q-O1")
    end

    def test_an_answer_to_the_last_wraps_to_the_first_waiting
        sign_in
        answer("O3")

        assert_equal "/l/#{@lid}#q-O1", last_response.headers["Location"]
        assert_equal "q-O1", link("q-O3")
    end

    def test_an_answer_skips_the_cards_already_answered
        sign_in
        answer("O3")
        answer("O1")

        assert_equal "/l/#{@lid}#q-O2", last_response.headers["Location"]
    end

    def test_with_nothing_left_the_page_stays_on_the_answered_card
        sign_in
        %w[O1 O3 O2].each { answer(it) }

        assert_equal "/l/#{@lid}#q-O2", last_response.headers["Location"]
        https "/l/#{@lid}"
        receipt = last_response.body[%r{<li[^>]* id="q-O2".*?</li>}m]

        assert_includes receipt, "Nothing left waiting on you in this ledger"
        refute_includes receipt, 'class="next-waiting"'
    end

    private

    # Each question offers options of its own: two alike are refused.
    def question(number)
        QUESTION.map do |arg|
            next arg unless arg == "A = one | B = two"

            "A = one#{number} | B = two#{number}"
        end
    end

    def answer(ref)
        say([["ref", ref], ["choice", "A = one#{ref[1..]}"]])
    end

    # The anchor the receipt of the card ANCHOR links to.
    def link(anchor)
        https "/l/#{@lid}"
        card = last_response.body[%r{<li[^>]* id="#{anchor}".*?</li>}m]
        card[/<a class="next-waiting" href="#([^"]+)"/, 1]
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
