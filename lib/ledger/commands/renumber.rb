# frozen_string_literal: true

module Ledger
    module Commands
        # `renumber PATH OLD NEW`: give the item OLD the unused id NEW. One
        # n changes; every structured reference names the row, so each
        # follows by key.
        class Renumber < CLI::Command
            USAGE = "PATH OLD NEW"
            SUMMARY = "give an item an unused id; its references follow"
            ID = /\A[PODCF][1-9]\d*\z/
            # The rows that point at an item of each kind, as [table,
            # condition on its row id].
            REFERENCES = {
                "P" => [%i[piece_links after_id], %i[questions by_id],
                        %i[question_sees piece_id],
                        %i[question_pictures pending_id]],
                "D" => [%i[piece_links criterion_id],
                        %i[question_sees criterion_id]],
                "C" => [%i[question_sees constraint_id]],
                "F" => [%i[question_sees fact_id]],
                "O" => []
            }.freeze

            private

            def flags(parser) = dry_run(parser)

            def run(path, old, new)
                shapes(old, new)
                result = write(path, own: new) do |change|
                    renumber(change, old, new, Address.parse(path))
                end
                emit(result, path, first: new,
                                   lines: ["renumbered #{old} -> #{new}: its " \
                                           "heading and #{result.value} " \
                                           "reference(s)"])
                0
            end

            def shapes(old, new)
                unless ID.match?(old) && ID.match?(new)
                    refuse("OLD and NEW are ids like P3 (P, O, C, F or D, " \
                           "then digits)")
                end
                refuse("#{old} and #{new} are not the same kind") unless
                    old[0] == new[0]
                refuse("OLD and NEW are the same") if old == new
            end

            # -> how many rows reference the item, once its n is NEW.
            def renumber(change, old, new, address)
                table, row = heading(change, old, address)
                held(change, old)
                unused(change, new)
                change.update(table, row[:id], n: new[1..].to_i)
                raise_counter(change, new)
                references(change.ledger_id, old[0], row[:id])
            end

            def heading(change, old, address)
                change.resolve(old)
            rescue Unknown
                refuse("#{old} heads no item in #{address}")
            end

            def held(change, old)
                held = db[:inbox_entries].where(ledger_id: change.ledger_id,
                                                ref: old, taken_id: nil)
                                         .order(:id).select_map(:n)
                return if held.empty?

                refuse("the inbox holds #{held.map { "N#{it}" }.join(", ")} " \
                       "not taken, about #{old}; file and take it first")
            end

            # NEW was never given (the counter) and names no inbox entry.
            def unused(change, new)
                ledger_id = change.ledger_id
                last = db[:counters].where(ledger_id:, kind: new[0]).get(:last)
                given = new[1..].to_i <= last.to_i
                return unless given || named?(ledger_id, new)

                refuse("#{new} heads an item, is named by a reference, or " \
                       "was given before")
            end

            def named?(ledger_id, new)
                db[:inbox_entries].where(ledger_id:, ref: new).any?
            end

            # U3: NEW is given now, so the counter never gives it again.
            def raise_counter(change, new)
                db[:counters].where(ledger_id: change.ledger_id, kind: new[0])
                             .update(last: new[1..].to_i)
            end

            def references(ledger_id, kind, row_id)
                rows = REFERENCES.fetch(kind).sum do |table, column|
                    db[table].where(column => row_id).count
                end
                rows + db[:links].where(ledger_id:)
                                 .where(Sequel.|({ from_kind: kind,
                                                   from_row: row_id },
                                                 { to_kind: kind,
                                                   to_row: row_id }))
                                 .count
            end

            def db = journal.db
        end
    end
end
