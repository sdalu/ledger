# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# The tray sent in one request: every item checked by the rules of its
# single send, all of them filed in one write, each its own entry; one
# item refused and none is filed, the answer naming each item refused.
class TrayTest < ViewerTest
    include LedgerFixture
    include Sends

    ROUTE = ["--route", "sonnet, effort: low"].freeze
    VERIFIED = ["--status", "verified", "--verified-by", "me", "--evidence",
                "suite green", "--problem", "the fix is not committed",
                "--risk", "2/10 — the fix waits",
                "--no-picture", "a wording change"].freeze
    WORD = { "ref" => "P2", "word" => "commit" }.freeze
    COMMENT = { "ref" => "P1", "text" => "which lexer?" }.freeze
    DROP = { "ref" => "O1", "word" => "drop", "text" => "" }.freeze
    # An empty comment, a word not awaited, an empty question, a comment
    # on a piece the ledger does not hold.
    BAD = [COMMENT.merge("text" => " "), WORD.merge("word" => "deploy"),
           { "ref" => "O1", "comment" => "1", "text" => "" },
           { "ref" => "P7", "text" => "gone" }].freeze
    # An answer, a note, the Close, a picture asked, the order.
    ALONE = [{ "ref" => "O1", "choice" => "A = one", "text" => "" },
             { "ref" => "", "text" => "a note" },
             { "ref" => "close", "text" => "" },
             { "ref" => "P1", "picture" => "svg", "text" => "the table" },
             { "ref" => "order", "order" => "P1", "text" => "" }].freeze

    # P1 planned, P2 verified and awaiting commit.
    def build_fixture
        super
        ledger("piece", "new", *ROUTE, "--title", "write the lexer")
        ledger("piece", "new", *ROUTE, "--title", "fix the reorder",
               *VERIFIED)
        ledger("piece", "P2", "--awaits", "commit")
    end

    def tray(*items, token: token())
        say([["items", JSON.generate(items)]], route: "say-batch", token:)
    end

    def refused = JSON.parse(last_response.body)

    # KEYS of each item refused.
    def refused_items(*keys)
        refused["items"].map { it.values_at(*keys) }
    end

    # The events that filed the ledger's entries.
    def filing_events
        rows = inbox_rows.map { it[:id] }
        @journal.db[:event_rows].where(tbl: "inbox_entries", row_id: rows)
                .select_map(:event_id).uniq
    end

    def test_a_word_a_comment_and_a_drop_are_filed_in_one_write
        sign_in
        tray(WORD, COMMENT, DROP)

        assert_equal 303, last_response.status
        assert_equal(
            [{ "id" => "N1", "ref" => "P2", "word" => "commit", "text" => "" },
             { "id" => "N2", "ref" => "P1", "text" => "which lexer?" },
             { "id" => "N3", "ref" => "O1", "word" => "drop", "text" => "" }],
            entries.map { it.except("at") }
        )
        assert_equal 1, filing_events.length
    end

    def test_one_item_refused_files_none_and_is_named
        sign_in
        tray(WORD, COMMENT.merge("word" => "commit"))

        assert_equal 409, last_response.status
        assert_equal [[1, "P1", 409]], refused_items("item", "ref", "status")
        assert_includes refused_items("why")[0][0], "P1 awaits no word now"
        assert_empty entries
    end

    def test_each_item_is_checked_as_its_single_send
        sign_in
        tray(*BAD)

        assert_equal 400, last_response.status
        assert_equal [[400, "Nothing to send."], [400, "P2 awaits commit."],
                      [400, "Nothing to send."]],
                     refused_items("status", "why").first(3)
        assert_equal [0, 1, 2, 3], refused_items("item").flatten
        assert_equal 409, refused_items("status")[3][0]
    end

    def test_an_item_sees_the_items_before_it_as_sent
        sign_in
        tray(WORD, { "ref" => "P2", "word" => "drop", "text" => "" })

        assert_equal 409, last_response.status
        assert_includes refused["items"][0]["why"], "P2 already has a word"
        assert_includes refused["items"][0]["why"], "tray item 1"
        assert_empty entries
    end

    def test_what_is_sent_on_its_own_is_refused_from_the_tray
        sign_in
        tray(*ALONE)

        sent_alone = refused_items("status", "why").map do |status, why|
            [status, why.end_with?("not from the tray.")]
        end

        assert_equal 400, last_response.status
        assert_equal [[400, true]] * 5, sent_alone
    end

    def test_a_tray_of_an_earlier_page_is_refused_and_kept
        sign_in
        tray(WORD, token: "old")

        assert_equal 403, last_response.status
        assert_match(%r{\Aapplication/json}, last_response.content_type)
        assert_includes refused["why"], "the tray is kept"
        assert_empty entries
    end

    def test_no_list_of_items_is_refused
        sign_in
        say([%w[items x]], route: "say-batch")

        assert_equal 400, last_response.status
        say([%w[items []]], route: "say-batch")

        assert_equal 400, last_response.status
        assert_empty entries
    end
end
