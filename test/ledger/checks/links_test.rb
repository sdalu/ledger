# frozen_string_literal: true

require_relative "runner_test"

# links: the after graph never loops, and a link's target is a row of
# its kind in this ledger.
class LinksChecksTest < CheckCase
    def test_an_after_loop_fails_links
        a = piece
        b = piece
        piece
        after(a, b)
        after(b, a)

        assert_fails "links", "after: loops through P1, P2"
    end

    def test_a_target_of_another_kind_or_ledger_fails_links
        x = decision
        @rows.insert(:links, kind: "answers", from_kind: "X", from_row: x,
                             to_kind: "O", to_row: 999)

        assert_fails "links", "X1 (answers: no O row 999 in this ledger)"
    end

    def test_a_link_without_its_target_is_refused
        x = decision
        assert_raises(Sequel::NotNullConstraintViolation) do
            @rows.insert(:links, kind: "answers", from_kind: "X",
                                 from_row: x, to_kind: "O", to_row: nil)
        end
    end

    def test_a_target_that_exists_passes
        @rows.insert(:links, kind: "answers", from_kind: "X",
                             from_row: decision, to_kind: "O",
                             to_row: question)

        assert_passes "links"
    end

    def decision
        @rows.insert(:decisions, n: @rows.next_id("X"), date: "2026-11-20",
                                 body: "keep it", by: "me")
    end
end
