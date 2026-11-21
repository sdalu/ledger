# frozen_string_literal: true

require "test_helper"

class IndexTest < ViewerTest
    def test_a_program_without_a_session_is_refused
        https "/"

        assert_equal 401, last_response.status
        refute_includes last_response.body, "alpha"
    end

    def test_a_browser_without_a_session_is_sent_to_sign_in
        https "/", :get, nil, html: true

        assert_equal 302, last_response.status
        assert_equal "/sign-in", last_response.headers["Location"]
    end

    def test_the_index_lists_the_ledger_after_sign_in
        sign_in
        https "/"

        body = last_response.body

        assert_predicate last_response, :ok?
        ["alpha", "<h1>What waits on you</h1>", "Nothing waits on you.",
         '<section class="ledgers">'].each { assert_includes body, it }
        assert_includes last_response.headers["Content-Type"], "text/html"
    end

    def test_a_ledger_name_is_escaped
        Fixture.ledger(@journal, File.join(@dir, "<b>x/LEDGER.md"),
                       project: "<b>x")
        sign_in
        https "/"

        assert_includes last_response.body, "&lt;b&gt;x"
        refute_includes last_response.body, "<b>x"
    end

    def test_a_ledger_links_to_its_page_by_the_hash_of_its_path
        sign_in
        https "/"
        lid = Digest::SHA1.hexdigest(Fixture.alpha(@dir))[0, 10]

        assert_includes last_response.body, %(href="/l/#{lid}")
    end

    # A closed ledger keeps its live one's address: it has no URL.
    def test_a_closed_ledger_is_not_listed
        @journal.db[:ledgers].insert(
            place: File.join(@dir, "beta"), name: "", project: "beta",
            created_at: 0, closed_at: 1
        )
        sign_in
        https "/"

        refute_includes last_response.body, "beta"
    end

    def test_a_new_event_moves_the_stamp
        sign_in
        https "/stamp"
        before = last_response.body
        Ledger::Write.run(@journal, Fixture.alpha(@dir), "touch", []) { nil }
        https "/stamp"

        refute_equal before, last_response.body
    end

    def test_the_stylesheet_is_the_one_in_public
        https "/viewer.css"

        assert_equal File.binread(@config.stylesheet), last_response.body
    end

    def test_unknown_paths_have_a_page
        sign_in
        https "/nowhere"

        assert_equal 404, last_response.status
        assert_includes last_response.body, "Not found"
    end
end
