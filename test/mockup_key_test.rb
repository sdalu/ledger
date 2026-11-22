# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# The key in the path of a mockup's files (MockupToken), which a frame
# with no session carries: what it opens, and what it does not.
class MockupKeyTest < ViewerTest
    include LedgerFixture

    PICTURES = { "pic.svg" => "<svg/>",
                 "deck/index.html" => "<p>deck</p>",
                 "deck/css/style.css" => "p {}" }.freeze

    def build_fixture
        super
        place(PICTURES)
    end

    def key(lid = @lid, now: Time.now)
        LedgerViewer::MockupToken.issue(Fixture::SECRET, lid, now:)
    end

    def test_a_valid_key_serves_the_file_without_a_session
        https "/m/k/#{key}/#{@lid}/pic.svg"

        assert_predicate last_response, :ok?
        assert_equal "<svg/>", last_response.body
        assert_equal LedgerViewer::Headers::MOCKUP_CSP,
                     last_response.headers["Content-Security-Policy"]
        assert_equal "no-store", last_response.headers["Cache-Control"]
    end

    def test_a_directorys_own_files_are_served_under_the_key
        https "/m/k/#{key}/#{@lid}/deck/css/style.css"

        assert_equal "p {}", last_response.body
    end

    def test_an_expired_key_is_not_found_not_a_sign_in
        https "/m/k/#{key(now: Time.now - 7200)}/#{@lid}/pic.svg"

        assert_equal 404, last_response.status
    end

    def test_another_ledgers_key_is_not_found
        https "/m/k/#{key("0123456789")}/#{@lid}/pic.svg"

        assert_equal 404, last_response.status
    end

    def test_a_tampered_or_malformed_key_is_not_found
        payload, mac = key.split(".")
        ["#{payload}.#{mac.tr("A-Za-z", "B-ZAb-za")}", "#{payload}.", "x",
         "#{mac}.#{payload}"].each do |bad|
            https "/m/k/#{bad}/#{@lid}/pic.svg"

            assert_equal 404, last_response.status, bad
        end
    end

    def test_a_key_does_not_open_a_write_or_another_path
        https "/m/k/#{key}/#{@lid}/pic.svg", :post

        refute_predicate last_response, :ok?
        https "/m/#{@lid}/pic.svg"

        assert_equal 401, last_response.status
    end

    def test_a_signed_out_page_carries_no_key
        https "/l/#{@lid}"

        assert_equal 401, last_response.status
        refute_includes last_response.body, "/m/k/"
    end
end
