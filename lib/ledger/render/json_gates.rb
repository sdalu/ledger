# frozen_string_literal: true

require "ledger/render/refs"

module Ledger
    module Render
        class Json
            # A piece's gates and its helper's report: `gates`, one per
            # name in the order first recorded, each with the time of its
            # state; `report`, its status line and the lines after it, or
            # null.
            class Gates
                def initialize(snapshot, context)
                    @context = context
                    @gates = Refs.group(snapshot.piece_gates, :piece_id)
                    @reports = snapshot.piece_reports.to_h do |row|
                        [row[:piece_id], row]
                    end
                end

                def call(piece)
                    { gates: @gates.fetch(piece[:id], []).map { gate(it) },
                      report: report(@reports[piece[:id]]) }
                end

                private

                def gate(row)
                    { name: row[:name], state: row[:state],
                      detail: row[:detail], at: at(row) }
                end

                def report(row)
                    return unless row

                    { status: row[:status], lines: row[:body].to_s.split("\n"),
                      at: at(row) }
                end

                def at(row)
                    Json.time(@context.events.dig(row[:event_id], :at))
                end
            end
        end
    end
end
