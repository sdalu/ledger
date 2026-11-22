# frozen_string_literal: true

require "ledger/text/risk"
require "ledger/text/step_risk"

module Ledger
    module Render
        class Json
            # A piece's two risks: `step_risk`, the highest step risk of
            # the words it awaits (Text::StepRisk), null when none is
            # weighed; `work_risk`, the last dispatch's rated RISK, else
            # the piece's own rating (Text::Risk.work), null when neither
            # is rated; and `irreversible`, which raises the step risk.
            class Risks
                def initialize(snapshot, derive)
                    @derive = derive
                    @last = snapshot.piece_assessments
                                    .group_by { it[:piece_id] }
                                    .transform_values(&:last)
                end

                def call(piece)
                    irreversible = piece[:irreversible]
                    words = @derive.awaits(piece).map(&:first)
                    { irreversible:,
                      step_risk: Text::StepRisk.max(words, irreversible:),
                      work_risk: work(piece) }
                end

                private

                def work(piece)
                    last = @last[piece[:id]]
                    dispatched = last && [last[:risk_rating], last[:risk_text]]
                    Text::Risk.work([piece[:risk_rating], piece[:risk]],
                                    dispatched).first
                end
            end
        end
    end
end
