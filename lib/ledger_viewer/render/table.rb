# frozen_string_literal: true

require_relative "helpers"
require_relative "text"

module LedgerViewer
    module Render
        # A row of the index's table of ledgers, with what the rows are
        # sorted by: [rank, the name as it is
        # escaped, lid, html].
        class Table
            def initialize(scope) = @scope = scope

            def row(lid, name, reading)
                rank, label = reading.summary
                state, needs = reading.state_cell(label)
                changed = Helpers.when_text(reading.updated)
                html = @scope.partial("index/row",
                                      lid:, name:, state:, needs:, changed:,
                                      counts: reading.counts,
                                      kind: Helpers::KIND[rank])
                [rank, Text.escape(name), lid, html]
            end
        end
    end
end
