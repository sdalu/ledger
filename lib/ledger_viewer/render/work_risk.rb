# frozen_string_literal: true

require "ledger/text/risk"

module LedgerViewer
    module Render
        # The text that rates a piece's work, "N/10 — what": its last
        # dispatch's rated RISK, else its own (Ledger::Text::Risk.work),
        # the source of the number show --json gives as work_risk.
        module WorkRisk
            module_function

            def text(piece)
                last = piece.fetch("assessments", []).last
                dispatched = last && last["risk"].values_at("rating", "text")
                own = (piece["risk"] || {}).values_at("rating", "text")
                Ledger::Text::Risk.work(own, dispatched).last.to_s
            end
        end
    end
end
