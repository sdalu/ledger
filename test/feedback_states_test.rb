# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# What a card says about its state: a question held by a deferred piece
# says what it waits for; the head says how many sent entries are unread
# and that no session is woken while the waker is off; the last answer says
# nothing is left waiting.
class FeedbackStatesTest < ViewerTest
    include LedgerFixture
    include Sends

    ROUTE = ["--route", "sonnet, effort: low"].freeze

    def build_fixture
        super
        ledger("piece", "new", *ROUTE, "--title", "write the lexer")
        ledger("piece", "P1", "--status", "deferred",
               "--until", "the grammar is frozen")
        ledger("ask", "which tool?", "--title", "Lexer tool",
               "--problem", "two tools", "--risk", "2/10 — rework",
               "--by", "P1", "--no-picture", "a choice of words")
    end

    def card(anchor)
        https "/l/#{@lid}"
        last_response.body[%r{<li[^>]* id="#{anchor}".*?</li>}m]
    end

    def test_a_question_held_by_a_deferred_piece_says_what_it_waits_for
        sign_in

        assert_includes card("q-O2"),
                        "Not ready to answer. Waits for P1, deferred until " \
                        "the grammar is frozen. It moves to Waiting on you " \
                        "when P1 is verified."
        refute_includes card("q-O2"), "still preparing"
    end

    def test_a_question_held_by_a_planned_piece_keeps_its_sentence
        ledger("piece", "P1", "--status", "planned")
        sign_in

        assert_includes card("q-O2"), "P1 (planned) is still preparing"
    end

    def head
        https "/l/#{@lid}"
        last_response.body[%r{<header class="ledger-head">.*?</header>}m]
    end

    def test_the_head_counts_the_sent_entries_while_the_waker_is_off
        sign_in
        refute_includes head, "waker-unread"
        say([%w[ref O1], ["choice", "A = one"]])
        part = head

        assert_includes part, '<form class="waker-unread" ' \
                              'data-key="waker-unread"'
        assert_includes part, "1 sent, not read yet — no session is woken " \
                              "while the waker is off"
        assert_includes part, %(action="/l/#{@lid}/waker")
        assert_includes part, %(name="waker" value="on")
    end

    def test_a_sent_card_carries_no_waker_note
        sign_in
        say([%w[ref O1], ["choice", "A = one"]])

        refute_includes card("q-O1"), "No session is woken"
    end

    def test_the_head_says_nothing_of_it_once_the_waker_is_on
        sign_in
        say([%w[waker on]], route: "waker")
        say([%w[ref O1], ["choice", "A = one"]])

        refute_includes head, "waker-unread"
    end

    def test_the_last_answer_says_nothing_is_left_waiting_on_the_user
        sign_in
        say([%w[ref O1], ["choice", "A = one"]])
        sent = card("q-O1")

        assert_includes sent, '<p class="next-waiting is-none" ' \
                              'role="status" tabindex="-1">Nothing left ' \
                              "waiting on you in this ledger</p>"
        assert_includes sent, "not read by the session yet"
    end
end
