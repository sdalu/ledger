# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# What a screen reader needs from the markup: an id used once on a page
# so a label names its own control, and a link whose name says where it
# leads.
class PageIdsTest < ViewerTest
    include LedgerFixture

    ROUTE = ["--route", "sonnet, effort: low"].freeze

    def page_ids
        https "/l/#{@lid}"
        last_response.body.scan(/\sid="([^"]+)"/).flatten
    end

    def test_no_id_repeats_on_a_page_with_a_question_and_a_piece
        ledger("piece", "new", *ROUTE, "--title", "write the lexer")
        sign_in

        assert_empty page_ids.tally.select { |_, n| n > 1 }.keys
    end

    def test_the_picture_label_names_the_textarea
        sign_in
        page_ids

        assert_includes last_response.body, %(for="picture-q-O1-text")
        assert_includes last_response.body, %(<textarea id="picture-q-O1-text")
    end

    def test_the_index_answer_link_names_the_question_and_its_ledger
        sign_in
        https "/"
        link = last_response.body[%r{<a class="answer".*?</a>}m]

        assert_match(%r{Answer<span class="visually-hidden"> .+ in \w+</span>},
                     link)
    end
end
