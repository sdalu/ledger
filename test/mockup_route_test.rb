# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# A ledger's pictures through the whole app: who may see them, what
# they are served as, the policy the Python viewer sends with them, and
# that nothing outside the folder is reached.
class MockupRouteTest < ViewerTest
    include LedgerFixture

    def test_a_picture_is_served_as_what_it_is
        picture("pic.svg")
        sign_in
        https "/m/#{@lid}/pic.svg"

        assert_predicate last_response, :ok?
        assert_equal "<svg/>", last_response.body
        assert_equal "image/svg+xml", last_response.headers["Content-Type"]
    end

    def test_a_picture_carries_the_mockup_policy_and_no_cache
        picture("pic.svg")
        sign_in
        https "/m/#{@lid}/pic.svg"
        headers = last_response.headers

        assert_equal python_csp["mockup"], headers["Content-Security-Policy"]
        assert_equal "no-store", headers["Cache-Control"]
        assert_equal "nosniff", headers["X-Content-Type-Options"]
    end

    def test_a_picture_in_a_folder_and_a_percent_encoded_one_are_served
        picture("sub/a b.png", "png")
        sign_in
        https "/m/#{@lid}/sub/a%20b.png"

        assert_equal "png", last_response.body
        assert_equal "image/png", last_response.headers["Content-Type"]
    end

    def test_a_name_is_decoded_once
        picture("a%41.png", "literal")
        picture("aA.png", "decoded twice")
        sign_in
        https "/m/#{@lid}/a%2541.png"

        assert_equal "literal", last_response.body
    end

    def test_a_plus_is_a_plus
        picture("a+b.png", "plus")
        sign_in
        https "/m/#{@lid}/a+b.png"

        assert_equal "plus", last_response.body
    end

    def test_nothing_outside_the_folder_is_served
        picture("pic.svg")
        File.write(File.join(@dir, "roots/gamma/.claude/secret.html"), "x")
        File.symlink("../../../../elsewhere/beta/LEDGER.md",
                     File.join(File.dirname(@ledger), "mockups/leak.txt"))
        sign_in
        ["../secret.html", "%2e%2e/secret.html", "leak.txt", "notes.md",
         "missing.svg", "."].each do |name|
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
        picture("pic.svg")
        https "/m/#{@lid}/pic.svg"

        assert_equal 401, last_response.status
    end
end
