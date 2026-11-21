# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# The stamp of one ledger (/stamp?lid=LID), which its page carries and
# watches, so that a write to another ledger leaves the page alone. Two
# live ledgers here, alpha and gamma: with one, its stamp and every
# ledger's would be the same.
class LedgerStampTest < ViewerTest
    include LedgerFixture

    def test_a_ledger_page_carries_its_own_ledgers_stamp
        sign_in
        https "/l/#{@lid}"
        page = last_response.body[/data-stamp="(\h+)"/, 1]

        assert_equal page, stamp(@lid)
        refute_equal page, stamp
    end

    def test_a_write_to_another_ledger_moves_every_stamp_but_this_ones
        sign_in
        mine = stamp(@lid)
        all = stamp
        Ledger::Write.run(@journal, Fixture.alpha(@dir), "touch", []) { nil }

        assert_equal mine, stamp(@lid)
        refute_equal all, stamp
    end

    def test_a_write_to_the_ledger_moves_its_stamp
        sign_in
        before = stamp(@lid)
        Ledger::Write.run(@journal, @ledger, "touch", []) { nil }

        refute_equal before, stamp(@lid)
    end

    # A page of a ledger closed or never there learns it changed.
    def test_an_unknown_or_closed_ledger_has_a_stamp_no_live_one_has
        sign_in
        live = [stamp(@lid), stamp(alpha)]
        unknown = stamp("0123456789")
        close(@ledger)

        assert_match(/\A\h{16}\z/, unknown)
        refute_includes live, unknown
        refute_includes live, stamp(@lid)
    end

    private

    # /stamp, or with `lid` that ledger's.
    def stamp(lid = nil)
        https(lid ? "/stamp?lid=#{lid}" : "/stamp")
        last_response.body
    end

    def alpha = Digest::SHA1.hexdigest(Fixture.alpha(@dir))[0, 10]

    def close(address)
        @journal.db[:ledgers].where(id: @journal.ledger(address)[:id])
                .update(closed_at: 1)
    end
end
