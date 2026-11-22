# frozen_string_literal: true

require "ledger/render/refs"

module Ledger
    module Render
        # A question as its line under Open: `- O3: title: detail`, then
        # the fields in the order `ask` writes them, the picture last.
        class QuestionLine
            SEES = { "C" => :constraint_id, "D" => :criterion_id,
                     "F" => :fact_id, "P" => :piece_id }.freeze

            def initialize(snapshot, refs)
                @refs = refs
                @numbers = snapshot.pieces.to_h { [it[:id], it[:n]] }
                %i[choices items sees pictures].each do |kind|
                    rows = snapshot[:"question_#{kind}"]
                    instance_variable_set(:"@#{kind}",
                                          Refs.group(rows, :question_id))
                end
            end

            def call(question)
                line = "- O#{question[:n]}: #{question[:title]}: " \
                       "#{question[:detail]}"
                fields(question).reduce(line) do |text, (name, value)|
                    "#{text} — #{name}: #{value}"
                end + Refs.tail(question[:tail]) + pictures(question)
            end

            private

            def fields(question)
                [["problem", question[:problem]], ["risk", question[:risk]],
                 ["items", items(question)], ["choices", choices(question)],
                 ["recommend", question[:recommend]], ["by", by(question)],
                 ["see", sees(question)]]
                    .reject { |_, value| value.nil? || value.empty? }
            end

            def by(question)
                @refs["P", question[:by_id]] if question[:by_id]
            end

            def items(question)
                @items.fetch(question[:id], []).map { it[:text] }.join(" | ")
            end

            def choices(question)
                rows = @choices.fetch(question[:id], [])
                rows.map { option(it) }.join(" | ")
            end

            def option(choice)
                "#{words(choice)}#{picture_of(choice)}"
            end

            def words(choice)
                label, effect, cost = choice.values_at(:label, :effect, :cost)
                return label if effect.to_s.empty? && cost.to_s.empty?

                cost = "; #{cost}" unless cost.to_s.empty?
                "#{label} = #{effect}#{cost}"
            end

            def picture_of(choice)
                " — picture: #{choice[:picture]}" if choice[:picture]
            end

            def sees(question)
                rows = @sees.fetch(question[:id], [])
                rows.map { see_id(it) }.join(", ")
            end

            def see_id(see)
                kind, column = SEES.find { |_, col| see[col] }
                @refs[kind, see[column]]
            end

            def pictures(question)
                rows = @pictures.fetch(question[:id], [])
                rows.map { " — mockup: #{picture(it)}" }.join
            end

            def picture(row)
                return row[:name] if row[:name]

                "pending (P#{@numbers.fetch(row[:pending_id])})"
            end
        end
    end
end
