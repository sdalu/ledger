# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# A ledger's page and its pictures, through the whole app: who may see
# them, the headers the Python viewer sends, the form token, and what
# a send answers until the next piece takes it.
class LedgerPageTest < ViewerTest
    include LedgerFixture

    def test_a_program_without_a_session_is_refused_the_page
        https "/l/#{@lid}"

        assert_equal 401, last_response.status
        refute_includes last_response.body, "Which one"
    end

    def test_the_page_after_sign_in_is_the_ledgers
        sign_in
        https "/l/#{@lid}"
        body = last_response.body

        assert_predicate last_response, :ok?
        assert_includes body, "<h1>gamma</h1>"
        assert_includes body, "Which one"
        assert_includes body, %(action="/l/#{@lid}/say")
        assert_includes last_response.headers["Content-Type"], "text/html"
    end

    def test_a_page_carries_the_python_viewers_headers
        sign_in
        csp = python_csp

        ["/", "/l/#{@lid}"].each do |path|
            https path
            headers = last_response.headers

            assert_equal csp["page"], headers["Content-Security-Policy"], path
            assert_equal "no-store", headers["Cache-Control"], path
            assert_equal "nosniff", headers["X-Content-Type-Options"], path
        end
    end

    def test_an_unknown_ledger_is_not_found
        sign_in
        https "/l/0123456789"

        assert_equal 404, last_response.status
    end

    def test_the_forms_carry_the_sessions_token
        sign_in
        https "/l/#{@lid}"
        mine = tokens(last_response.body)
        https "/l/#{@lid}"

        assert_equal 1, mine.uniq.length
        assert_match(/\A\h{64}\z/, mine.first)
        assert_equal mine, tokens(last_response.body)
    end

    def test_another_session_has_another_token
        sign_in
        https "/l/#{@lid}"
        mine = tokens(last_response.body).first
        clear_cookies
        sign_in("bob")
        https "/l/#{@lid}"

        refute_equal mine, tokens(last_response.body).first
    end

    def tokens(body)
        body.scan(/name="token" value="([^"]*)"/).flatten
    end
end
