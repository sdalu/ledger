# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# A ledger's pictures from the journal, through the whole app: who may
# see them, what they are served as, the policy sent with them, a
# picture placed as a directory, and nothing that is not a picture of
# that ledger.
class MockupRouteTest < ViewerTest
    include LedgerFixture

    PICTURES = { "pic.svg" => "<svg/>", "sub/b.png" => "png",
                 "deck/index.html" => "<p>deck</p>",
                 "deck/css/style.css" => "p {}" }.freeze

    # gamma, O1 showing pic.svg, the directory sub and the directory deck.
    def build_fixture
        super
        place(PICTURES)
    end

    def test_a_picture_is_served_as_what_it_is
        sign_in
        https "/m/#{@lid}/pic.svg"

        assert_predicate last_response, :ok?
        assert_equal "<svg/>", last_response.body
        assert_equal "image/svg+xml", last_response.headers["Content-Type"]
    end

    def test_a_picture_carries_the_mockup_policy_and_no_cache
        sign_in
        https "/m/#{@lid}/pic.svg"
        headers = last_response.headers

        assert_equal LedgerViewer::Headers::MOCKUP_CSP,
                     headers["Content-Security-Policy"]
        assert_equal "no-store", headers["Cache-Control"]
        assert_equal "nosniff", headers["X-Content-Type-Options"]
    end

    def test_an_image_in_a_directory_is_served_as_one
        sign_in
        https "/m/#{@lid}/sub/b.png"

        assert_equal "png", last_response.body
        assert_equal "image/png", last_response.headers["Content-Type"]
    end

    def test_each_file_of_a_directory_is_served_under_its_name
        sign_in
        https "/m/#{@lid}/deck/index.html"

        assert_equal "<p>deck</p>", last_response.body
        https "/m/#{@lid}/deck/css/style.css"

        assert_equal "p {}", last_response.body
        assert_includes last_response.headers["Content-Type"], "text/css"
    end

    # A copy of pic.svg under another name is one blob, served as both.
    def test_every_picture_is_served_as_placed
        place("copy.svg" => "<svg/>")
        sign_in
        PICTURES.merge("copy.svg" => "<svg/>").each do |name, body|
            https "/m/#{@lid}/#{name}"

            assert_equal body, last_response.body, name
        end
        assert_equal 4, @journal.db[:picture_blobs].count
    end

    # The /m/k/TOKEN/LID the page draws its pictures from.
    def keyed
        last_response.body[%r{/m/k/[\w.-]+/#{@lid}}] or flunk "no keyed path"
    end

    def test_a_directory_with_an_index_is_drawn_by_it
        sign_in
        https "/l/#{@lid}"
        body = last_response.body

        assert_includes body, %(data-src="#{keyed}/deck/index.html")
        assert_includes body, %(<iframe src="#{keyed}/deck/index.html")
        assert_includes body, %(data-src="#{keyed}/pic.svg")
        refute_includes body, "placed as a directory"
    end

    def test_a_directory_with_one_image_is_drawn_as_that_image
        sign_in
        https "/l/#{@lid}"

        assert_includes last_response.body,
                        %(<img src="#{keyed}/sub/b.png")
    end

    # A row for a second page of the placed directory NAME.
    def second_page(name)
        pictures = @journal.db[:pictures]
        pictures.insert(pictures.where(name:).first.except(:id)
                                .merge(path: "b.html"))
    end

    # A directory of two pages and no index: the command refuses to place
    # one, so the second page is a row an older journal could hold.
    def test_a_directory_of_two_pages_is_flagged_not_drawn
        place("two/a.html" => "<p>a</p>")
        second_page("two")
        sign_in
        https "/l/#{@lid}"

        assert_includes last_response.body,
                        "mockup two: placed as a directory, not drawn here"
        refute_includes last_response.body, "#{keyed}/two/"
    end

    def test_nothing_but_a_picture_of_the_ledger_is_served
        sign_in
        ["deck", "deck/", "deck/missing.html", "../LEDGER.md",
         "%2e%2e/LEDGER.md", "missing.svg", "pic.svg/x", "."].each do |name|
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
        https "/m/#{@lid}/pic.svg"

        assert_equal 401, last_response.status
    end
end
