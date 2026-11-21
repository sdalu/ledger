# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# A comment on a question that answers nothing: filed as an entry with
# `comment`, refused empty or on a question no longer open, never an
# answer to replace, and the card stays a question to answer.
class QuestionCommentTest < ViewerTest
    include LedgerFixture
    include Sends

    def ask(text) = say([%w[ref O1], %w[comment 1], ["text", text]])

    def card
        https "/l/#{@lid}"
        last_response.body[%r{<li[^>]* id="q-O1".*?</li>}m]
    end

    def test_a_comment_is_filed_and_the_page_goes_back_to_its_card
        sign_in
        ask("which file?")

        assert_equal 303, last_response.status
        assert_equal "/l/#{@lid}#q-O1", last_response.headers["Location"]
        assert_equal({ "id" => "N1", "ref" => "O1", "comment" => true,
                       "text" => "which file?" }, entries.first.except("at"))
    end

    def test_an_empty_comment_is_refused
        sign_in
        ask("  ")

        assert_equal 400, last_response.status
        assert_empty entries
    end

    def test_a_comment_on_a_question_no_longer_open_is_refused
        sign_in
        say([%w[ref O9], %w[comment 1], %w[text why]])

        assert_equal 409, last_response.status
        assert_includes last_response.body, "send it as a note"
        assert_empty entries
    end

    def test_an_answer_after_a_comment_names_nothing_it_replaces
        sign_in
        ask("which file?")
        say([%w[ref O1], ["choice", "A = one"]])

        assert_equal 303, last_response.status
        refute entries.last.key?("replaces")
    end

    def test_the_card_stays_answerable_and_says_what_was_asked
        sign_in
        ask("which file?")
        shown = card

        assert_includes shown, "Send answer to O1"
        assert_includes shown, "Ask about O1"
        assert_match(/asked: N1, sent \d\d:\d\d · awaiting filing/, shown)
        refute_includes shown, "Change your answer"
    end
end
