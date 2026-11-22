# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# The card of a piece out or back: its gates as chips coloured by state
# with their time on hover, the last failure's detail under them, the
# helper's report folded; a verified piece draws none of them.
class GatesCardTest < ViewerTest
    include LedgerFixture

    PIECE = ["new", "--title", "Port the runner", "--route",
             "opus, effort: high", "--no-picture", "internal"].freeze

    def setup
        super
        ledger("piece", *PIECE)
        ledger("piece", "P1", "--status", "out", "--session", "s1")
        ledger("piece", "P1", "--gate", "rubocop: passed")
        ledger("piece", "P1", "--gate", "unit: failed (2 failures)")
        report = File.join(@dir, "report.txt")
        File.write(report, "DONE_WITH_CONCERNS\none <b>\ntwo\n")
        ledger("piece", "P1", "--status", "back", "--handback",
               "--report", report)
    end

    def card
        sign_in
        https "/l/#{@lid}"
        last_response.body[/<li[^>]* id="piece-P1".*/m]
    end

    def test_the_gates_are_chips_coloured_by_state_their_time_on_hover
        html = card
        chip = '<span class="gate is-passed" tabindex="0" ' \
               'style="anchor-name: --tip-\d+" aria-describedby="tip-\d+">' \
               'rubocop passed</span><span class="tip"[^>]*>' \
               'passed \d{4}-\d\d-\d\d \d\d:\d\d</span>'

        assert_match Regexp.new(chip), html
        assert_includes html, %(<span class="gate is-failed")
    end

    def test_the_last_failure_says_its_detail_under_the_chips
        assert_includes card, %(<p class="gate-failure">unit: 2 failures</p>)
    end

    def test_the_report_is_folded_under_its_status
        assert_includes card, '<details class="report"><summary>Report: ' \
                              "DONE_WITH_CONCERNS</summary>" \
                              '<div class="report-lines">one &lt;b&gt;' \
                              "\ntwo</div></details>"
    end

    def test_a_verified_piece_draws_neither
        ledger("piece", "P1", "--status", "verified", "--verified-by", "me",
               "--evidence", "suite green")
        sign_in
        https "/l/#{@lid}"

        refute_includes last_response.body, %(class="gates")
        refute_includes last_response.body, %(class="report")
    end
end
