# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# A word card's two risks: each word button carries its step meter
# ('step N/10', the combined one the highest of its words, none for
# other), and the RAID line rates the work ('work N/10'), from the last
# dispatch once the piece was dispatched, else from its own --risk.
class RiskMetersCardTest < ViewerTest
    include LedgerFixture

    PIECE = ["new", "--title", "Ship the sort", "--route",
             "sonnet, effort: low", "--status", "verified",
             "--verified-by", "me", "--evidence", "suite green",
             "--problem", "not pushed", "--risk", "3/10 — the sort waits",
             "--no-picture", "wording", "--awaits", "commit, push"].freeze
    ANNOUNCE = "ANNOUNCE\nWHAT: w\nWHY: y\nWHICH: sonnet, effort: low\n" \
               "RISK: 6/10 — a caller missed\nMODE: attended\n"

    def card
        sign_in
        https "/l/#{@lid}"
        last_response.body[%r{<li[^>]* id="p-P1".*?</li>}m]
    end

    # The step band and label of each word button, by its value; the
    # drop is no word.
    def steps
        card.scan(%r{name="word"\ value="([^"]+)"[^>]*>.*?</button>
                     (?:<span\ class="step\ ([^"]+)">.*?(step\ \d+/10))?}mx)
            .reject { it.first == "drop" }
    end

    def test_each_button_carries_its_step_the_combined_one_the_highest
        ledger("piece", *PIECE)

        assert_equal [["commit, push", "is-mid", "step 4/10"],
                      ["commit", "is-low", "step 1/10"]], steps
    end

    def test_an_irreversible_piece_adds_three_to_each_step
        ledger("piece", *PIECE)
        ledger("piece", "P1", "--irreversible")

        assert_equal [["commit, push", "is-high", "step 7/10"],
                      ["commit", "is-mid", "step 4/10"]], steps
    end

    def test_other_draws_no_step_meter
        ledger("piece", *PIECE)
        ledger("piece", "P1", "--awaits", "other (a look at the shots)")

        refute_includes card, %(class="step)
    end

    def test_the_raid_line_rates_the_work_from_the_piece_own_risk
        ledger("piece", *PIECE)

        assert_includes card, "work 3/10</span> the sort waits"
        refute_includes card, "risk 3/10"
    end

    def test_a_dispatch_rates_the_work_in_place_of_the_own_risk
        ledger("piece", *PIECE)
        file = File.join(@dir, "announce.txt")
        File.write(file, ANNOUNCE)
        ledger("piece", "P1", "--announce", file)

        assert_includes card, "work 6/10</span> a caller missed"
        assert_includes card, %(data-risk="6")
    end
end
