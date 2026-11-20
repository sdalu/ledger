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
        FileUtils.mkdir_p(File.join(@dir, "roots/<b>x/.git"))
        File.write(File.join(@dir, "roots/<b>x/LEDGER.md"), "# Ledger\n")
        sign_in
        https "/"

        assert_includes last_response.body, "&lt;b&gt;x"
        refute_includes last_response.body, "<b>x"
    end

    def test_a_ledger_links_to_its_page_by_the_hash_of_its_path
        sign_in
        https "/"
        path = File.join(@dir, "roots/alpha/LEDGER.md")
        lid = Digest::SHA1.hexdigest(path)[0, 10]

        assert_includes last_response.body, %(href="/l/#{lid}")
    end

    def test_a_ledger_outside_the_roots_is_never_listed
        sign_in
        https "/"

        refute_includes last_response.body, "beta"
    end

    def test_the_stylesheet_is_the_one_beside_the_engine
        https "/viewer.css"

        assert_equal File.read(@config.stylesheet), last_response.body
    end

    def test_unknown_paths_have_a_page
        sign_in
        https "/nowhere"

        assert_equal 404, last_response.status
        assert_includes last_response.body, "Not found"
    end
end
