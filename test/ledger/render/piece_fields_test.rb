# frozen_string_literal: true

require_relative "helper"

# A piece's fields after its title: their order, the id lists and the
# prose after them, awaits and scope.
class PieceFieldsTest < RenderTest
    FIELDS = { status: "out", claimed_by: "s", problem: "pr",
               risk: "7/10 — loss", plan: "pl", done_when: "dw",
               evidence: "ev" }.freeze

    def test_r5_fields_come_in_the_order_piece_writes_them
        snap = snapshot do |change|
            first = piece(change)
            criterion(change, text: "a check")
            piece(change, **FIELDS)
            link_fields(change, first)
        end

        assert_equal "- P2 [out] sonnet, effort: low — Piece 2 — problem: " \
                     "pr — risk: 7/10 — loss — plan: pl — scope: commit = " \
                     "merge it — done when: dw — after: P1 — for: D1 — " \
                     "awaits: commit — evidence: ev", line(snap, "P2")
    end

    def test_r10_an_id_list_is_comma_and_space_separated
        snap = snapshot do |change|
            ids = Array.new(3) { piece(change) }
            last = piece(change)
            ids.each_with_index do |id, i|
                change.insert(:piece_links, piece_id: last, kind: "after",
                                            position: i, after_id: id)
            end
        end

        assert_includes line(snap, "P4"), " — after: P1, P2, P3"
    end

    def test_the_prose_after_the_ids_is_kept_where_it_was
        snap = snapshot do |change|
            first = piece(change, after_tail: " — asked turn 3")
            second = piece(change)
            change.insert(:piece_links, piece_id: second, kind: "after",
                                        position: 0, after_id: first)
            change.update(:pieces, second, after_tail: " — asked turn 3")
        end

        assert_equal "- P2 [planned] sonnet, effort: low — Piece 2 — " \
                     "after: P1 — asked turn 3", line(snap, "P2")
    end

    def test_a_tail_stored_without_its_dash_gets_one
        snap = snapshot do |change|
            first = piece(change)
            second = piece(change, after_tail: "asked turn 3")
            change.insert(:piece_links, piece_id: second, kind: "after",
                                        position: 0, after_id: first)
        end

        assert_includes line(snap, "P2"), " — after: P1 — asked turn 3"
    end

    def test_awaits_words_other_and_scope
        snap = snapshot do |change|
            id = piece(change)
            [["start", nil], ["commit", nil], ["other", "look at it"]]
                .each_with_index do |(word, what), i|
                change.insert(:piece_awaits, piece_id: id, position: i,
                                             word:, what:)
            end
        end

        assert_includes line(snap, "P1"),
                        " — awaits: start, commit, other (look at it)"
    end

    private

    def link_fields(change, after)
        id = change.resolve("P2").last[:id]
        crit = change.resolve("D1").last[:id]
        change.insert(:piece_links, piece_id: id, kind: "after",
                                    position: 0, after_id: after)
        change.insert(:piece_links, piece_id: id, kind: "for",
                                    position: 0, criterion_id: crit)
        change.insert(:piece_awaits, piece_id: id, position: 0,
                                     word: "commit")
        change.insert(:piece_scopes, piece_id: id, position: 0,
                                     word: "commit", text: "merge it")
    end
end
