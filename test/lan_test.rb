# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# A caller inside a lan network needs no sign-in; every other caller
# does, and what a form must carry holds for both.
class LanTest < ViewerTest
    include LedgerFixture
    include Sends

    def inside = { "REMOTE_ADDR" => "192.0.2.9" }
    def outside = { "REMOTE_ADDR" => "198.51.100.9" }

    def setup
        super
        config = Fixture.config(@dir, lan: ["192.0.2.0/24"])
        @app = LedgerViewer::Web.configured(config, journal: @journal).new
    end

    def test_a_caller_in_the_network_reads_the_pages_without_signing_in
        ["/", "/l/#{@lid}"].each do |path|
            https path, :get, nil, inside

            assert_predicate last_response, :ok?, path
        end
        assert_includes last_response.body, "Which one"
    end

    def test_a_caller_in_the_network_sends_an_answer
        say([%w[ref], %w[text hello]], token: lan_token, headers: inside)

        assert_equal 303, last_response.status
        assert_equal(["hello"], entries.map { it["text"] })
        assert_equal ["viewer:lan:192.0.2.9"], actors
    end

    def test_a_caller_outside_is_sent_to_sign_in_or_refused
        https "/l/#{@lid}", :get, nil, outside
        assert_equal 401, last_response.status

        header "Accept", "text/html"
        https "/l/#{@lid}", :get, nil, outside
        assert_equal 302, last_response.status
        assert_includes last_response.headers["Location"], "/sign-in"
    end

    def test_a_caller_outside_cannot_send_with_the_lan_token
        say([%w[ref], %w[text x]], token: lan_token, headers: outside)

        assert_equal 401, last_response.status
        assert_empty entries
    end

    def test_a_forwarded_address_does_not_make_a_caller_inside
        https "/l/#{@lid}", :get, nil,
              outside.merge("HTTP_X_FORWARDED_FOR" => "192.0.2.9",
                            "HTTP_FORWARDED" => "for=192.0.2.9")

        assert_equal 401, last_response.status
    end

    def test_a_wrong_token_is_not_taken
        say([%w[ref], %w[text x]], token: "wrong", headers: inside)

        refute_equal 303, last_response.status
        assert_empty entries
    end

    def test_the_origin_and_the_site_still_hold
        { "HTTP_ORIGIN" => "https://evil.example",
          "HTTP_SEC_FETCH_SITE" => "cross-site" }.each do |name, value|
            say([%w[ref], %w[text x]], token: lan_token,
                                       headers: inside.merge(name => value))

            assert_equal 403, last_response.status, name
        end
        assert_empty entries
    end

    def test_an_address_that_is_no_network_stops_the_start
        assert_raises(LedgerViewer::ConfigError) do
            Fixture.config(@dir, lan: ["not-a-network"])
        end
    end

    private

    # The token the pages give a caller with no session.
    def lan_token
        https "/l/#{@lid}", :get, nil, inside
        last_response.body[/name="token" value="([^"]*)"/, 1]
    end
end
