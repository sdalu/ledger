# frozen_string_literal: true

module Ledger
    module Commands
        # What `show PATH P<n>` says of a piece's history, a line each:
        # its returns (`return: env, from back, TIME`), the dispatches
        # announced (`assessment: TIME, sonnet, …`), its gates (`gate:
        # unit failed (2 failures), TIME`) and its report, the status line
        # then its lines indented.
        module ShowHistory
            # The item's keys these lines say, left out of its scalars.
            KEYS = %i[returns assessments gates report].freeze

            private

            def history(item)
                [*returns(item), *assessments(item), *gates(item),
                 *report(item)]
            end

            def returns(item)
                item.fetch(:returns, []).map do |row|
                    "return: #{row[:cause]}, from #{row[:from]}, #{row[:at]}"
                end
            end

            # `assessment: TIME, sonnet, effort: medium, axis: stakes
            # (low), risk: 2/10, attended`, what the block left out left out.
            def assessments(item)
                item.fetch(:assessments, []).map do |row|
                    "assessment: #{[row[:at], *assessed(row)].join(", ")}"
                end
            end

            def assessed(row)
                rating = row.dig(:risk, :rating)
                [row[:model], row[:effort]&.then { "effort: #{it}" },
                 row[:axis]&.then { "axis: #{it} (#{row[:axis_level]})" },
                 "risk: #{rating ? "#{rating}/10" : "unrated"}",
                 row[:mode_attended] ? "attended" : "unattended"].compact
            end

            def gates(item)
                item.fetch(:gates, []).map do |row|
                    detail = " (#{row[:detail]})" if row[:detail]
                    "gate: #{row[:name]} #{row[:state]}#{detail}, #{row[:at]}"
                end
            end

            def report(item)
                row = item[:report] or return []

                ["report: #{row[:status]}, #{row[:at]}",
                 *row[:lines].map { "  #{it}" }]
            end
        end
    end
end
