# frozen_string_literal: true

require_relative "say_form"

module LedgerViewer
    module Render
        # The fold proposing an order for the planned pieces: proposing
        # an order is its own act, after the pieces, not a fourth piece.
        class Order
            LABEL = "Proposed order of the planned pieces"

            def initialize(kit)
                @kit = kit
                @reading = kit.reading
            end

            def html
                list = planned
                return "" unless list.length > 1

                spec = SayForm::BLANK.with(ref: "order", order: list,
                                           label: LABEL)
                form = @kit.say.html(spec)
                @kit.scope.partial("ledger/flight_order", lid: @kit.lid, form:)
            end

            private

            # The planned pieces in an order the server accepts: a piece
            # after those it waits for, the ledger's order otherwise.
            def planned
                after = @reading.pieces.to_h { [it["id"], it["after"]] }
                todo = after.keys.select { statuses[it] == "planned" }
                todo.length.times.map do
                    free = todo.index { !after.fetch(it, []).intersect?(todo) }
                    todo.delete_at(free || 0)
                end
            end

            def statuses = @reading.statuses
        end
    end
end
