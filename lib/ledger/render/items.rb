# frozen_string_literal: true

module Ledger
    module Render
        # The one-line items that need no other table: the lines of the
        # Goal block, Done when, Constraints, Facts and Decisions.
        module Items
            module_function

            # The lines under a Goal label: the session's Title, In short
            # and Context, then the user's words quoted.
            def goal(row)
                [("Title: #{row[:title]}" if row[:title]),
                 ("In short: #{row[:short]}" if row[:short]),
                 ("Context: #{row[:context]}" if row[:context]),
                 *row[:quote].split("\n", -1).map { quoted(it) }].compact
            end

            # "Goal (2026-11-19, verbatim):", from the stamp stored without
            # its parentheses.
            def goal_label(row) = "Goal (#{row[:stamp]}):"

            def criterion(row)
                "- [#{row[:mark]}] D#{row[:n]}: #{row[:text]}" \
                    "#{criterion_reason(row)}"
            end

            def constraint(row) = "- C#{row[:n]}: #{row[:text]}"

            def fact(row) = "- F#{row[:n]}: #{row[:text]} — #{row[:pointer]}"

            def decision(row)
                note = " (#{row[:note]})" if row[:note]
                "- #{row[:date]} — #{row[:body]} — by #{row[:by]}#{note}"
            end

            def quoted(line) = line.strip.empty? ? ">" : "> #{line}"

            # " — why: W" for a criterion not met, " — evidence: E" for
            # the others (an empty evidence leaves the bare label), nothing
            # when the row has neither.
            def criterion_reason(row)
                return " — why: #{row[:why]}" if row[:why]
                return unless row[:evidence]

                evidence = row[:evidence]
                evidence.empty? ? " — evidence:" : " — evidence: #{evidence}"
            end
        end
    end
end
