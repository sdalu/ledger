# frozen_string_literal: true

require "minitest/autorun"

require "ledger/text/codes"

# The codes of a text: one or two capitals and digits standing alone,
# whose letter is not a kind, outside quotes, code spans and URLs.
class CodesTest < Minitest::Test
    Codes = Ledger::Text::Codes

    def test_codes_standing_alone
        assert_equal %w[W1 S4 H12], Codes.find("W1, S4 and H12 (W1 again).")
        assert_equal %w[PR12], Codes.find("as PR12 said")
    end

    def test_kinds_are_not_codes
        assert_empty Codes.find("P3, O2, D1, C23, F4, X2, N1, Z3, E9, L2, G2")
    end

    def test_quotes_code_and_urls_are_set_aside
        assert_empty Codes.find('"W1 holds" “S4” `H12` https://x.org/W1')
    end

    def test_inside_a_path_or_identifier_is_not_a_code
        assert_empty Codes.find("a/W1 W1/b W1.rb x.W1 x_W1 x-W1 W1-x W1x XAW1")
    end
end
