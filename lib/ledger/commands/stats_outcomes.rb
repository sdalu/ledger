# frozen_string_literal: true

module Ledger
    module Commands
        # The section `outcomes` of `stats` (Outcomes): the rows counted by
        # kind and rule, overall and per ledger. Over every ledger the
        # count is every row's, those no ledger was known for included;
        # over one ledger, its rows alone.
        class StatsOutcomes
            HEAD = ["kind", "rule", "count", "by ledger"].freeze

            # IDS, the ledgers counted; ALL, every row counted.
            def initialize(db, ids, all:)
                rows = db[:outcomes]
                rows = rows.where(ledger_id: ids) unless all
                @counts = rows.group_and_count(:kind, :rule, :ledger_id)
                              .order(:kind, :rule, :ledger_id).all
            end

            # The section's lines, nil when no outcome was recorded.
            def text
                return if @counts.empty?

                rows = groups.map do |(kind, rule), counts|
                    [kind, rule, total(counts).to_s, ledgers(counts)]
                end
                ["outcomes", StatsTable.text([HEAD, *rows], right: [2])]
                    .join("\n")
            end

            def json
                groups.map do |(kind, rule), counts|
                    { kind:, rule:, count: total(counts),
                      ledgers: by_ledger(counts) }
                end
            end

            private

            def groups = @counts.group_by { it.values_at(:kind, :rule) }
            def total(counts) = counts.sum { it[:count] }

            def by_ledger(counts)
                counts.select { it[:ledger_id] }
                      .to_h { ["L#{it[:ledger_id]}", it[:count]] }
            end

            def ledgers(counts)
                shown = by_ledger(counts).map { |id, n| "#{id} #{n}" }
                shown.empty? ? "-" : shown.join(", ")
            end
        end
    end
end
