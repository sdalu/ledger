# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# A picture asked of the session from a card that has none: filed as an
# entry on the card's id with `picture`, refused without text, of a kind
# not offered or on a card no longer on the page; no answer and no word,
# so what follows it is sent as before; the card says it was asked.
class PictureRequestTest < ViewerTest
    include LedgerFixture
    include Sends

    ROUTE = ["--route", "sonnet, effort: low"].freeze
    VERIFIED = ["--status", "verified", "--verified-by", "me", "--evidence",
                "suite green", "--problem", "the fix is not committed",
                "--risk", "2/10 — the fix waits",
                "--no-picture", "a wording change"].freeze

    def request(*sent) = say(%w[ref picture text].zip(sent))

    def card(anchor)
        https "/l/#{@lid}"
        last_response.body[%r{<li[^>]* id="#{anchor}".*?</li>}m]
    end

    def lexer = ledger("piece", "new", *ROUTE, "--title", "write the lexer")

    def test_a_request_on_a_question_is_filed_and_goes_back_to_its_card
        sign_in
        request("O1", "svg", "the two layouts")

        assert_equal 303, last_response.status
        assert_equal "/l/#{@lid}#q-O1", last_response.headers["Location"]
        assert_equal({ "id" => "N1", "ref" => "O1", "picture" => "svg",
                       "text" => "the two layouts" },
                     entries.first.except("at"))
    end

    def test_a_request_on_a_piece_goes_back_to_its_card
        lexer
        sign_in
        request("P1", "any", "the token table")

        assert_equal "/l/#{@lid}#piece-P1", last_response.headers["Location"]
        assert_equal "any", entries.first["picture"]
    end

    def test_an_empty_text_and_an_unknown_kind_are_refused
        sign_in
        request("O1", "svg", "  ")

        assert_equal 400, last_response.status
        request("O1", "gif", "the layouts")

        assert_equal 400, last_response.status
        assert_empty entries
    end

    def test_an_id_no_longer_a_card_is_refused
        sign_in
        request("O9", "svg", "the layouts")

        assert_includes last_response.body, "send it as a note"
        request("P9", "svg", "the layouts")

        assert_equal 409, last_response.status
        assert_empty entries
    end

    def test_the_fold_is_offered_on_a_question_without_a_picture
        sign_in
        shown = card("q-O1")

        ["Request a picture", "What should it show?", "Request picture",
         %(name="picture" value="any" checked)]
            .each { assert_includes shown, it }
    end

    def test_no_fold_on_a_question_with_a_picture
        place("look.svg" => "<svg/>")
        sign_in

        refute_includes card("q-O1"), "Request a picture"
    end

    def test_the_fold_on_a_piece_without_a_side_and_not_with_one
        lexer
        sign_in

        assert_includes card("piece-P1"), "Request a picture"
        file = File.join(@dir, "before.svg")
        File.write(file, "<svg/>")
        ledger("mockup", file, "--piece", "P1", "--before")

        refute_includes card("piece-P1"), "Request a picture"
    end

    def test_after_a_send_the_card_says_it_was_asked_and_offers_no_fold
        sign_in
        request("O1", "text", "the flow")
        shown = card("q-O1")

        assert_match(/picture asked: N1, sent \d\d:\d\d · not read by/,
                     shown)
        refute_includes shown, "Request a picture"
        assert_includes shown, "Send answer to O1"
    end

    def test_your_messages_names_the_kind
        sign_in
        request("O1", "screenshot", "the page")
        https "/l/#{@lid}"

        assert_includes last_response.body, "picture asked for O1 (screenshot)"
    end

    def test_an_answer_after_a_request_is_accepted_as_before
        sign_in
        request("O1", "svg", "the layouts")
        say([%w[ref O1], ["choice", "A = one"]])

        refute entries.last.key?("replaces")
        assert_equal "A = one", entries.last["choice"]
    end

    def test_a_word_after_a_request_is_accepted_as_before
        ledger("piece", "new", *ROUTE, "--title", "Fix the reorder",
               *VERIFIED, "--awaits", "commit")
        sign_in
        request("P1", "svg", "the diff")

        assert_includes card("p-P1"), "picture asked: N1"
        say([%w[ref P1], %w[word commit]])

        assert_equal 303, last_response.status
        refute entries.last.key?("replaces")
        assert_equal "commit", entries.last["word"]
    end
end
