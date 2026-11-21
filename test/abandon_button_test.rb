# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# The ledger's Abandon on its page: offered on any live ledger, after the
# Close when the Close is offered, folded behind the same confirmation,
# filed once as an entry the session files with `ledger close --abandon
# --take`.
class AbandonButtonTest < ViewerTest
    include LedgerFixture
    include Sends

    FOLD = %r{<details class="abandon-fold".*?</details>}m

    def page
        https "/l/#{@lid}"
        last_response.body
    end

    def test_a_ledger_not_ready_offers_the_abandon_behind_a_confirmation
        sign_in
        fold = page[FOLD]

        refute_nil fold
        assert_includes fold, "Abandon the ledger</summary>"
        assert_includes fold, "Abandon this ledger unfinished?"
        assert_includes fold, "the pieces not finished are dropped"
        assert_includes fold, "Its history stays in the journal."
        assert_match(/<button type="submit" class="a-abandon">Yes, abandon/,
                     fold)
    end

    def test_a_ready_ledger_offers_it_after_the_close
        finish
        sign_in
        body = page

        assert_operator body.index(%(<details class="close-fold")), :<,
                        body.index(%(<details class="abandon-fold"))
    end

    def test_the_abandon_is_filed_and_the_page_goes_back_to_it
        sign_in
        say([%w[ref abandon], %w[text enough]])

        assert_equal 303, last_response.status
        assert_equal "/l/#{@lid}#abandon", last_response.headers["Location"]
        assert_equal([{ "ref" => "abandon", "text" => "enough" }],
                     entries.map { it.slice("ref", "text") })
    end

    def test_an_abandon_sent_is_shown_as_asked_and_refused_again
        sign_in
        say([%w[ref abandon]])
        body = page

        assert_includes body, "abandon asked"
        refute_match FOLD, body
        say([%w[ref abandon]])

        assert_equal [409, 1], [last_response.status, entries.length]
        assert_includes last_response.body, "already asked"
    end

    def test_the_session_abandons_it_taking_the_entry
        sign_in
        say([%w[ref abandon]])
        out = ledger("close", "--abandon", "--take", "N1")

        assert_match(/\Aafter action:.*\n(?:.*\n)*abandoned: /, out)
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
