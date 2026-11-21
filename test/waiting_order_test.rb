# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# What waits on the user is in one order on the ledger page, the index
# queue's: the oldest wait first. Gamma's P1 awaits its start since two
# hours, O1 was asked an hour ago, so P1 leads the head's next step,
# Waiting on you and the side list, although a question comes first
# when the waits tie.
class WaitingOrderTest < ViewerTest
    include LedgerFixture

    HOUR = 3_600_000

    def build_fixture
        at(3) { ledger("new", *GOAL) }
        at(2) do
            ledger("piece", "new", "--route", "sonnet, effort: low",
                   "--title", "write the lexer", "--awaits", "start",
                   "--problem", "the lexer waits for a go",
                   "--risk", "2/10 — nothing breaks", "--plan", "start it")
        end
        at(1) { ledger("ask", *QUESTION) }
    end

    def test_the_oldest_wait_leads_the_head_the_section_and_the_side_list
        page = body
        step = page[/<a class="next-step"[^>]*href="([^"]+)"/, 1]
        waiting = page[%r{<section class="waiting".*?</section>}m]
        nav = page[%r{<nav class="question-nav".*?</nav>}m]

        assert_equal "#p-P1", step
        assert_operator waiting.index('id="p-P1"'), :<,
                        waiting.index('id="q-O1"')
        assert_operator nav.index('href="#p-P1"'), :<,
                        nav.index('href="#q-O1"')
    end

    def test_the_index_queue_has_the_same_order
        sign_in
        https "/"
        queue = last_response.body

        assert_operator queue.index("#p-P1"), :<, queue.index("#q-O1")
    end

    private

    def body
        sign_in
        https "/l/#{@lid}"
        last_response.body
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
