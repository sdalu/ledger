# frozen_string_literal: true

module Ledger
    module Commands
        # A table of `stats`: its columns as wide as their widest cell,
        # the counts (the columns RIGHT names) right-aligned.
        module StatsTable
            module_function

            def text(rows, right: [1])
                widths = rows.transpose.map { |column| column.map(&:size).max }
                rows.map { line(it, widths, right) }.join("\n")
            end

            def line(cells, widths, right)
                cells.zip(widths).each_with_index.map do |(cell, width), index|
                    next cell.rjust(width) if right.include?(index)

                    cell.ljust(width)
                end.join("  ").rstrip
            end

            def returns(counts)
                return "-" if counts.empty?

                counts.map { |cause, count| "#{cause} #{count}" }.join(", ")
            end
        end

        # The section `by assessment` of `stats` (Stats::Assessments):
        # one table by highest axis, one by model, each row a group's
        # dispatches, the pieces it first dispatched, those of them
        # verified at the first pass, and the returns by cause.
        class StatsAssessed
            HEAD = ["dispatches", "pieces", "verified first",
                    "returns"].freeze
            # The label of the dispatches that named no axis.
            UNSTATED = "unstated"

            def initialize(assessments)
                @assessments = assessments
            end

            # The section's lines, nil when no dispatch was announced.
            def text
                return unless @assessments.any?

                ["by assessment",
                 table("highest axis", @assessments.by_axis), "",
                 table("model", @assessments.by_model)].join("\n")
            end

            def json
                { by_axis: @assessments.by_axis.map { group(:axis, it) },
                  by_model: @assessments.by_model.map { group(:model, it) } }
            end

            private

            def table(name, groups)
                rows = [[name, *HEAD], *groups.map { cells(it) }]
                StatsTable.text(rows, right: [1, 2])
            end

            def cells(group)
                [group.label || UNSTATED, group.dispatches.to_s,
                 group.pieces.to_s,
                 "#{group.first_time}/#{group.pieces}",
                 StatsTable.returns(group.returns)]
            end

            def group(key, group)
                { key => group.label, dispatches: group.dispatches,
                  pieces: group.pieces, verified_first: group.first_time,
                  returns: group.returns }
            end
        end
    end
end
