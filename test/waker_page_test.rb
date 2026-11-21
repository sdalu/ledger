# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# The waker on a ledger page: the switch in the head, which writes the
# `waker` event as the command does, and the ledger's wakes listed.
class WakerPageTest < ViewerTest
    include LedgerFixture
    include Sends

    def head
        https "/l/#{@lid}"
        last_response.body[%r{<header class="ledger-head">.*?</header>}m]
    end

    def waker = @journal.ledger(@ledger)[:waker]

    def switch(word, token: token(), headers: {})
        say([["waker", word]], route: "waker", token:, headers:)
    end

    def test_the_head_offers_to_switch_an_off_ledger_on
        sign_in
        part = head

        assert_includes part, %(action="/l/#{@lid}/waker")
        assert_includes part, %(name="waker" value="on")
        assert_includes part, "Waker off"
        refute_includes part, "waker-wakes"
    end

    def test_switching_goes_back_to_the_switch_now_on
        sign_in
        switch("on")

        assert_equal 303, last_response.status
        assert_equal "/l/#{@lid}#waker", last_response.headers["Location"]
        assert waker
        assert_includes head, %(name="waker" value="off")
    end

    def test_switching_writes_the_event_the_command_writes
        sign_in
        switch("on")
        event = @journal.db[:events].order(:id).last

        assert_equal %w[waker viewer:alice], event.values_at(:command, :actor)
    end

    def test_a_stale_token_or_another_origin_switches_nothing
        sign_in
        switch("on", token: "0" * 64)

        assert_equal 409, last_response.status
        switch("on", headers: { "HTTP_ORIGIN" => "https://example.com" })

        assert_equal 403, last_response.status
        refute waker
    end

    def test_a_word_but_on_or_off_is_refused
        sign_in
        switch("maybe")

        assert_equal 400, last_response.status
        refute waker
    end

    def test_the_page_lists_each_wake
        woken("socket", "posted")
        woken("resume", "copied c0ffee00-1111")
        sign_in
        part = head

        assert_includes part, "<summary>2 wakes</summary>"
        assert_includes part, "<td>2026-11-21 09:30</td><td>socket</td>" \
                              "<td>posted</td>"
        assert_includes part, "<td>resume</td><td>copied c0ffee00-1111</td>"
    end

    # A wakes row of the ledger, at 2026-11-21 09:30 local time.
    def woken(path, outcome)
        @journal.db[:wakes].insert(
            ledger_id: @journal.ledger(@ledger)[:id], session_id: "s-1",
            at: Time.new(2026, 11, 21, 9, 30).to_i * 1000, path:, outcome:
        )
    end
end
