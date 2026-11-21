# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# A ledger's pictures from the journal, through the whole app: who may
# see them, what they are served as, the policy sent with them, a
# picture placed as a directory, and nothing that is not a picture of
# that ledger.
class MockupRouteTest < ViewerTest
    include LedgerFixture

    PICTURES = { "pic.svg" => "<svg/>", "sub/b.png" => "png",
                 "deck/index.html" => "<p>deck</p>",
                 "deck/css/style.css" => "p {}" }.freeze

    # gamma, O1 showing pic.svg, the directory sub and the directory deck.
    def build_fixture
        super
        place(PICTURES)
    end

    def test_a_picture_is_served_as_what_it_is
        sign_in
        https "/m/#{@lid}/pic.svg"

        assert_predicate last_response, :ok?
        assert_equal "<svg/>", last_response.body
        assert_equal "image/svg+xml", last_response.headers["Content-Type"]
    end

    def test_a_picture_carries_the_mockup_policy_and_no_cache
        sign_in
        https "/m/#{@lid}/pic.svg"
        headers = last_response.headers

        assert_equal LedgerViewer::Headers::MOCKUP_CSP,
                     headers["Content-Security-Policy"]
        assert_equal "no-store", headers["Cache-Control"]
        assert_equal "nosniff", headers["X-Content-Type-Options"]
    end

    def test_an_image_in_a_directory_is_served_as_one
        sign_in
        https "/m/#{@lid}/sub/b.png"

        assert_equal "png", last_response.body
        assert_equal "image/png", last_response.headers["Content-Type"]
    end

    def test_each_file_of_a_directory_is_served_under_its_name
        sign_in
        https "/m/#{@lid}/deck/index.html"

        assert_equal "<p>deck</p>", last_response.body
        https "/m/#{@lid}/deck/css/style.css"

        assert_equal "p {}", last_response.body
        assert_includes last_response.headers["Content-Type"], "text/css"
    end

    def test_a_directory_is_flagged_on_the_card_not_drawn
        sign_in
        https "/l/#{@lid}"

        assert_includes last_response.body,
                        "mockup deck: placed as a directory"
        assert_includes last_response.body, %(data-src="/m/#{@lid}/pic.svg")
    end

    def test_nothing_but_a_picture_of_the_ledger_is_served
        sign_in
        ["deck", "deck/", "deck/missing.html", "../LEDGER.md",
         "%2e%2e/LEDGER.md", "missing.svg", "pic.svg/x", "."].each do |name|
            https "/m/#{@lid}/#{name}"

            assert_equal 404, last_response.status, name
        end
    end

    def test_a_picture_of_an_unknown_ledger_is_not_found
        sign_in
        https "/m/0123456789/pic.svg"

        assert_equal 404, last_response.status
    end

    def test_a_picture_is_refused_without_a_session
        https "/m/#{@lid}/pic.svg"

        assert_equal 401, last_response.status
    end
end
