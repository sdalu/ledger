# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# A picture `prune-pictures` removed after an undo, which a restore then
# named again: the question names it, no row holds it, and it is not
# served.
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
end
