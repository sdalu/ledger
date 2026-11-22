# frozen_string_literal: true

require "ledger/hold"

module Ledger
    module Commands
        # The pieces a `piece --hold WHY` names (P<n>) must be pieces of
        # the ledger: a hold on a piece that cannot settle never clears.
        class PieceHold
            def initialize(change, opts)
                @change = change
                @opts = opts
            end

            def check
                @opts["hold"].to_s.scan(Hold::NAMED).flatten.each do |n|
                    @change.resolve("P#{n}")
                rescue Unknown
                    raise Refused, "P#{n} is no piece of this ledger"
                end
            end
        end
    end
end
