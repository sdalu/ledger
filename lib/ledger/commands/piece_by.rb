# frozen_string_literal: true

module Ledger
    module Commands
        # `piece --by X<n>`: the decision that led to the piece, written
        # as a led_to edge unless it is there already.
        class PieceBy
            BY = /\AX[1-9]\d*\z/

            def initialize(change, db, opts)
                @change = change
                @db = db
                @opts = opts
            end

            # The edge from the decision to PIECE (a row id).
            def link(piece)
                ref = @opts["by"]&.strip or return
                raise Refused, "--by takes a decision id, X<n>" unless
                    BY.match?(ref)

                n = @db[:pieces].where(id: piece).get(:n)
                @change.link("led_to", ref, "P#{n}") unless led?(ref, piece)
            end

            private

            def led?(ref, piece)
                from = @change.resolve(ref).last[:id]
                @db[:links].where(ledger_id: @change.ledger_id, kind: "led_to",
                                  from_row: from, to_kind: "P",
                                  to_row: piece).any?
            end
        end
    end
end
