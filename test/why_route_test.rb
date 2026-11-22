# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# The links page of a piece or a decision, through the whole app: its
# route, its stylesheet after the viewer's, the links to it from the
# ledger page, and nothing for an id that has no page.
class WhyRouteTest < ViewerTest
    include LedgerFixture

    # gamma, with the decision X1 and the piece P1.
    def build_fixture
        super
        ledger("decide", "keep the lexer — it works", "--by", "user",
               "--date", "2026-11-19")
        ledger("piece", "new", "--route", "sonnet, effort: low",
               "--title", "port the lexer", "--for", "D1")
    end

    def why(id) = "/l/#{@lid}/why/#{id}"

    def test_a_piece_and_a_decision_have_a_page
        sign_in
        %w[P1 X1].each do |id|
            https why(id)

            assert_predicate last_response, :ok?, id
            assert_includes last_response.body, %(id="links-title">Why )
        end
    end

    def test_the_page_leads_back_to_the_ledger_and_the_item_on_it
        sign_in
        https why("P1")
        body = last_response.body

        all = %(<p class="crumbs"><a href="/">All ledgers</a>)

        assert_includes body, %(#{all} / <a href="/l/#{@lid}">)
        assert_includes body,
                        %(Why <a class="id-link" href="/l/#{@lid}#piece-P1">)
        https why("X1")

        assert_includes last_response.body,
                        %(Why <a class="id-link" href="/l/#{@lid}#dec-0">)
    end

    def test_the_page_carries_the_links_stylesheet_after_the_viewers
        sign_in
        https why("P1")
        body = last_response.body
        viewer = body.index("--space-xs:")
        links = body.index(".links-columns {")

        assert viewer && links && viewer < links
    end

    def test_the_ledger_page_links_each_piece_and_decision_to_its_page
        sign_in
        https "/l/#{@lid}"

        assert_includes last_response.body, %(href="#{why("P1")}")
        assert_includes last_response.body, %(href="#{why("X1")}")
    end

    def test_an_id_with_no_page_is_not_found
        sign_in
        %w[P9 X9 O1 F1].each do |id|
            https why(id)

            assert_equal 404, last_response.status, id
        end
    end

    def test_a_caller_without_a_session_is_refused
        https why("P1")

        assert_equal 401, last_response.status
    end
end
