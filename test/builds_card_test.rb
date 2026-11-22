# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

# A question with a piece building it (piece --builds) is one card: its
# picker, then the piece's plan, risk and pictures, and one button that
# answers and starts; the piece has no card of its own while the
# question is open. The piece it made obsolete is in the record, its
# replacement a link.
class BuildsCardTest < ViewerTest
    include LedgerFixture
    include Sends

    PIECE = ["piece", "new", "--route", "sonnet, effort: low",
             "--awaits", "start", "--problem", "the lexer waits for a go",
             "--risk", "4/10 — a wrong lexer", "--no-picture",
             "no screen"].freeze

    def build_fixture
        super
        ledger(*PIECE, "--title", "write the old lexer")
        ledger(*PIECE, "--title", "write the lexer", "--plan",
               "the lexer the answer picks", "--builds", "O1")
        ledger("piece", "P1", "--status", "obsolete", "--obsoleted-by", "P2")
    end

    def page
        sign_in
        https "/l/#{@lid}"
        last_response.body
    end

    def waiting = page[%r{<section class="waiting".*?</section>}m]

    def test_one_card_holds_the_picker_the_piece_and_one_button
        card = waiting

        assert_equal ["q-O1"], card.scan(/<li[^>]* id="([qp]-[^"]+)"/).flatten
        assert_includes card, 'id="builds-P2"'
        assert_includes card, "the lexer the answer picks"
        assert_includes card, "4/10"
        assert_match(/data-start="P2"[^>]*>.*Answer and start P2/m, card)
        refute_includes card, "Send answer to O1"
        assert_operator card.index('name="choice"'), :<,
                        card.index('id="builds-P2"')
    end

    def test_the_piece_has_no_card_of_its_own
        refute_includes waiting, 'id="p-P2"'
        refute_includes waiting, 'id="p-P1"'
    end

    def test_the_obsolete_piece_links_its_replacement_in_the_record
        record = page[/<h2 id="record".*/m]

        assert_includes record, 'href="#piece-P2"'
        assert_match(%r{obsoleted by</span> <a[^>]*href="#piece-P2"}, record)
    end

    def test_the_answer_then_the_start_are_two_entries
        sign_in
        say([%w[ref O1], ["choice", "A = one"]])
        say([%w[ref P2], %w[word start]])

        assert_equal([["O1", "A = one"], %w[P2 start]],
                     entries.map { [it["ref"], it["choice"] || it["word"]] })
    end
end
