# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# A send, through the whole app: who may make one, what is filed in the
# ledger's inbox and where the page goes back to, and that a refused
# send writes nothing.
class InboxTest < ViewerTest
    include LedgerFixture
    include Sends

    def test_a_program_without_a_session_files_nothing
        https "/l/#{@lid}/say", :post, "token=x&ref=O1&choice=A+%3D+one"

        assert_equal 401, last_response.status
        assert_empty entries
    end

    def test_a_caller_without_a_session_files_nothing
        sign_in
        mine = token
        clear_cookies
        header "Authorization", "Bearer nonsense"
        say([%w[ref O1], ["choice", "A = one"]], token: mine)

        refute_equal 303, last_response.status
        assert_empty entries
    end

    def test_a_wrong_token_is_refused_and_the_text_shown_back
        sign_in
        say([%w[ref O1], ["choice", "A = one"], ["text", "my <reason>"]],
            token: "stale")

        assert_equal 403, last_response.status
        assert_includes last_response.body, "Not sent yet"
        assert_includes last_response.body, "my &lt;reason&gt;"
        assert_includes last_response.body, token
        assert_empty entries
    end

    def test_a_write_from_another_site_is_refused
        sign_in
        say([%w[ref O1], ["choice", "A = one"]],
            headers: { "HTTP_SEC_FETCH_SITE" => "cross-site" })

        assert_equal 403, last_response.status
        assert_empty entries
    end

    def test_an_answer_is_filed_and_the_page_goes_back_to_its_card
        sign_in
        say([%w[ref O1], ["choice", "A = one"], ["text", "why"]])

        assert_equal 303, last_response.status
        assert_equal "/l/#{@lid}#q-O1", last_response.headers["Location"]
        filed = entries.first
        assert_match(/\A\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\z/, filed.delete("at"))
        assert_equal({ "id" => "N1", "ref" => "O1", "choice" => "A = one",
                       "text" => "why" }, filed)
        assert_equal ["viewer:alice"], actors
    end

    def test_a_second_answer_must_say_it_replaces_the_first
        sign_in
        say([%w[ref O1], ["choice", "A = one"]])
        say([%w[ref O1], ["choice", "B = two"]])

        assert_equal 409, last_response.status
        assert_equal 1, entries.length
        say([%w[ref O1], ["choice", "B = two"], %w[replaces N1]])

        assert_equal 303, last_response.status
        assert_equal ["N1"], entries.last["replaces"]
    end

    def test_a_note_goes_back_to_the_messages
        sign_in
        say([%w[ref], ["text", "a note"]])

        assert_equal "/l/#{@lid}#inbox", last_response.headers["Location"]
        assert_equal({ "ref" => nil, "text" => "a note" },
                     entries.last.slice("ref", "text"))
    end

    def test_nothing_is_filed_for_an_empty_a_long_or_a_malformed_body
        sign_in
        https "/l/#{@lid}/say", :post, "", form

        assert_equal 413, last_response.status
        say([%w[ref], ["text", "x" * 4001]])

        assert_equal 400, last_response.status
        say([%w[ref], %w[text x]], route: "nowhere")

        assert_equal 404, last_response.status
        assert_empty entries
    end

    def test_an_invalid_escape_is_refused_before_the_route
        sign_in
        https "/l/#{@lid}/say", :post,
              "token=#{token}&ref=&text=a%zzb", form

        assert_equal 400, last_response.status
        assert_empty entries
    end

    def test_an_unknown_ledger_is_not_found
        sign_in
        https "/l/0123456789/say", :post, "token=#{token}&text=x", form

        assert_equal 404, last_response.status
    end
end
