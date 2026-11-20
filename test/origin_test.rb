# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# A form is taken only from a page of this viewer: its Origin is the
# scheme and host the request came to, as the Python viewer asks.
class OriginTest < ViewerTest
    include LedgerFixture
    include Sends

    def test_a_form_must_come_from_the_viewers_own_origin
        sign_in
        ["https://evil.example", "http://localhost", "https://localhost:1",
         "null", ""].each do |origin|
            say([%w[ref], %w[text x]], headers: { "HTTP_ORIGIN" => origin })

            assert_equal 403, last_response.status, origin
        end
        assert_empty lines
    end

    def test_a_form_without_an_origin_is_refused
        sign_in
        body = URI.encode_www_form([["token", token], %w[ref], %w[text x]])
        https "/l/#{@lid}/say", :post, body,
              "CONTENT_TYPE" => "application/x-www-form-urlencoded"

        assert_equal 403, last_response.status
        assert_includes last_response.body, "own page"
        assert_empty lines
    end

    def test_the_viewers_own_origin_is_taken
        sign_in
        say([%w[ref], %w[text x]])

        assert_equal 303, last_response.status
    end
end
