# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# A picture `prune-pictures` removed after an undo, which a restore then
# named again: the question names it, no row holds it, it is not served,
# and the page draws a "picture pruned" tile in its place.
class PrunedPictureTest < ViewerTest
    include LedgerFixture

    DAY_MS = 86_400_000

    # gamma, O1 showing pic.svg; the mockup undone, the picture pruned,
    # the undo restored over.
    def build_fixture
        super
        place("pic.svg" => "<svg/>")
        mark = @journal.db[:events].max(:id)
        ledger("undo")
        @journal.db[:events].update(at: Ledger::Write.now - (30 * DAY_MS))
        LedgerCommands.run(@journal, "prune-pictures", "--confirmed")
        ledger("restore", "--to", "E#{mark}")
    end

    def test_the_picture_row_is_gone_and_the_question_still_names_it
        assert_equal 0, @journal.db[:pictures].count
        assert_equal ["pic.svg"],
                     @journal.db[:question_pictures].select_map(:name)
    end

    def test_the_picture_is_not_served
        sign_in
        https "/m/#{@lid}/pic.svg"

        assert_equal 404, last_response.status
    end

    def test_the_page_answers_with_a_pruned_tile
        sign_in
        https "/l/#{@lid}"

        assert_predicate last_response, :ok?
        assert_includes last_response.body, "mockup pic.svg: picture pruned"
        refute_includes last_response.body, "/pic.svg\""
    end
end

# A piece whose before picture was pruned while it awaits its commit.
class PrunedSideTest < ViewerTest
    include LedgerFixture

    PIECE = ["new", "--title", "Fix the reorder", "--route",
             "sonnet, effort: low", "--status", "verified",
             "--verified-by", "me", "--evidence", "suite green",
             "--problem", "the fix is not committed",
             "--risk", "2/10 — the fix waits"].freeze

    def build_fixture
        super
        ledger("piece", *PIECE)
        %w[before after].each do |role|
            file = File.join(@dir, "#{role}.svg")
            File.write(file, "<svg/>")
            ledger("mockup", file, "--piece", "P1", "--#{role}")
        end
        ledger("piece", "P1", "--awaits", "commit, push")
        @journal.db[:pictures].where(name: "before.svg").delete
    end

    def test_the_card_says_the_picture_was_pruned
        sign_in
        https "/l/#{@lid}"

        assert_predicate last_response, :ok?
        assert_includes last_response.body, "picture pruned"
    end
end
