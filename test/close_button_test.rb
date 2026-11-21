# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# The ledger's Close on its page: offered only when the status line
# proposes it, folded so that a click opens the request and the form's
# button alone sends it, filed as an entry the session closes with
# `ledger close --take`.
class CloseButtonTest < ViewerTest
    include LedgerFixture
    include Sends

    def test_a_ledger_not_ready_offers_no_close_and_refuses_one
        sign_in
        https "/l/#{@lid}"

        refute_includes last_response.body, %(<details class="close-fold")
        say([%w[ref close]])

        assert_equal 409, last_response.status
        assert_includes last_response.body, "not ready to close"
        assert_empty entries
    end

    def test_a_ready_ledger_offers_the_close_behind_a_confirmation
        finish
        sign_in
        https "/l/#{@lid}"
        page = last_response.body

        assert_includes page, "Ready to close."
        fold = page[%r{<details class="close-fold".*?</details>}m]
        refute_nil fold
        assert_includes fold, "Close this ledger?"
        assert_match(/<button type="submit" class="a-close">Yes, close it/,
                     fold)
    end

    def test_the_close_is_filed_and_the_page_goes_back_to_it
        finish
        sign_in
        say([%w[ref close]])

        assert_equal 303, last_response.status
        assert_equal "/l/#{@lid}#close", last_response.headers["Location"]
        assert_equal([{ "ref" => "close", "text" => "" }],
                     entries.map { it.slice("ref", "text") })
    end

    def test_a_close_sent_is_shown_as_asked_and_not_offered_again
        finish
        sign_in
        say([%w[ref close]])
        https "/l/#{@lid}"
        page = last_response.body

        assert_includes page, "close asked"
        refute_includes page, %(<details class="close-fold")
        say([%w[ref close]])

        assert_equal [409, 1], [last_response.status, entries.length]
    end

    def test_the_session_closes_it_taking_the_entry
        finish
        sign_in
        say([%w[ref close], %w[text thanks]])
        out = ledger("close", "--take", "N1")

        assert_match(/\Aclosed: /, out)
        refute_nil @journal.db[:inbox_entries].get(:taken_id)
        https "/l/#{@lid}"

        assert_equal 404, last_response.status
    end

    private

    # Gamma finished: its question answered, its criterion met.
    def finish
        ledger("answer", "O1", "--decision", "\"A = one\" — simple")
        ledger("criterion", "D1", "--met", "seen")
    end
end
