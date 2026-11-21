# frozen_string_literal: true

require "ledger/render/refs"

module Ledger
    module Render
        # An assumption as its line under Assumptions: `- A1 [open] TEXT —
        # check: CHECK`, then what it rests on (`— see: F2, C1`), what
        # rests on it (`— for: P3, O2`) and, once settled, the fact that
        # settled it (`— by: F4`).
        class AssumptionLine
            SEES = { "C" => :constraint_id, "D" => :criterion_id,
                     "F" => :fact_id, "P" => :piece_id }.freeze

            def initialize(snapshot, refs = Refs.new(snapshot))
                @refs = refs
                @questions = snapshot.questions.to_h { [it[:id], it[:n]] }
                @sees = Refs.group(snapshot.assumption_sees, :assumption_id)
                @links = snapshot.assumption_links.group_by do |link|
                    link[:assumption_id]
                end
            end

            def call(row)
                parts = fields(row).reject { |_, text| text.empty? }
                                   .map { |name, text| "#{name}: #{text}" }
                ["- A#{row[:n]} [#{row[:state]}] #{row[:text]}", *parts]
                    .join(" — ")
            end

            def fields(row)
                { "check" => row[:check], "see" => sees(row).join(", "),
                  "for" => resting(row).join(", "), "by" => fact(row).to_s }
            end

            # The ids of the items ROW rests on, in position order.
            def sees(row)
                @sees.fetch(row[:id], []).map do |see|
                    kind, column = SEES.find { |_, col| see[col] }
                    @refs[kind, see[column]]
                end
            end

            # The ids of the pieces and questions resting on ROW, in link
            # order.
            def resting(row)
                @links.fetch(row[:id], []).map do |link|
                    next @refs["P", link[:piece_id]] if link[:piece_id]

                    "O#{@questions.fetch(link[:question_id])}"
                end
            end

            # F<n> of the fact that settled ROW, or nil.
            def fact(row) = row[:fact_id] && @refs["F", row[:fact_id]]
        end
    end
end
