# frozen_string_literal: true

require_relative "runner_test"

# codes: a code from elsewhere (W1) standing alone in an item's text
# fails unless an open question points with see: to an item naming it;
# the user's quoted words and code spans are not read.
class CodesChecksTest < CheckCase
    def test_a_detail_naming_w1_bare_fails
        question(detail: "Which cache policy holds under W1?")

        assert_fails "codes", "O1: W1"
    end

    def test_words_around_the_code_do_not_pass
        question(detail: "Which cache holds under W1 of the web baseline?")

        assert_fails "codes", "O1: W1"
    end

    def test_a_see_to_an_item_naming_it_passes
        fact = @rows.insert(:facts, n: @rows.next_id("F"),
                                    text: "`W1` is the web baseline's rule",
                                    pointer: "~/ai-tools/WEB-BASELINE.md")
        id = question(detail: "Which cache policy holds under W1?")
        @rows.insert(:question_sees, question_id: id, position: 0,
                                     fact_id: fact)

        assert_passes "codes"
    end

    def test_a_see_to_an_item_not_naming_it_still_fails
        fact = @rows.insert(:facts, n: @rows.next_id("F"), text: "sqlite",
                                    pointer: "journal.rb")
        id = question(detail: "Which cache policy holds under W1?")
        @rows.insert(:question_sees, question_id: id, position: 0,
                                     fact_id: fact)

        assert_fails "codes", "O1: W1"
    end

    def test_quotes_and_code_spans_are_not_read
        piece(detail: 'the user said "follow W1" and `S4` is a key')

        assert_passes "codes"
    end

    def test_kinds_paths_and_identifiers_are_not_codes
        piece(detail: "P3 waits; see doc/W1/x.md, w1.W2, H2O, the-S4 and " \
                      "https://x.org/?a=W1")

        assert_passes "codes"
    end

    def test_a_questions_own_items_are_not_codes
        id = question(["A = keep it", "B = drop the cache"],
                      recommend: "S1 A, S2 B")
        %w[S1 S2].each_with_index do |text, position|
            @rows.insert(:question_items, question_id: id, position:, text:)
        end

        assert_passes "codes"
    end

    def test_each_item_is_named_with_its_codes
        piece(title: "Radii under V1", plan: "then V2 and V1")
        @rows.insert(:facts, n: @rows.next_id("F"), text: "seen",
                             pointer: "T5, scratchpad/T5/a.out")

        assert_fails "codes", "P1: V1, V2; F1: T5"
    end

    def test_a_settled_piece_is_not_read
        piece(status: "verified", evidence: "ran", detail: "under W1")

        assert_passes "codes"
    end
end
