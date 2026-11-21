# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# An answered question's receipt: the option chosen is split at its first
# ':' or ';', so the collapsed row shows what was chosen and the open card
# the whole option.
class ReceiptTest < ViewerTest
    include LedgerFixture
    include Sends

    LONG = "C1 = Abandon: closes it unfinished; history kept"

    def build_fixture
        super
        ledger("ask", "Abandon?", "--title", "Abandon a ledger",
               "--problem", "x", "--risk", "3/10 — y",
               "--choices", "#{LONG} | C2 = Keep it; nothing",
               "--recommend", "C1, keeps the record",
               "--no-picture", "a choice of words")
    end

    def test_a_chosen_option_is_split_into_its_head_and_the_rest
        sign_in
        say([%w[ref O2], ["choice", LONG]])
        https "/l/#{@lid}"
        sent = last_response.body[%r{<li[^>]* id="q-O2".*?</li>}m]

        assert_includes sent,
                        %(chose <span class="sum-head">C1 = Abandon</span>)
        assert_includes sent,
                        %(<span class="sum-rest">: closes it unfinished; ) +
                        %(history kept</span>)
    end

    def test_an_option_without_a_colon_is_all_head
        sign_in
        say([%w[ref O1], ["choice", "A = one"]])
        https "/l/#{@lid}"

        assert_includes last_response.body,
                        %(<span class="sum-head">A = one</span>) +
                        %(<span class="sum-rest"></span>)
    end
end
