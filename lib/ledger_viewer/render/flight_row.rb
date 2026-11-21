# frozen_string_literal: true

require_relative "case"
require_relative "raid"
require_relative "text"
require_relative "why"

module LedgerViewer
    module Render
        # An unfinished piece with nothing to say yet, as one row of the
        # Unfinished pieces: its title, status, id and the icon to its
        # links page, opening into its card. The row keeps the card's id
        # (piece-P<n>), so a link to the piece lands on it and opens it.
        class FlightRow
            # The statuses a piece waits in before anything is at stake.
            QUIET = %w[planned deferred].freeze

            # Whether PIECE has nothing to say: planned or deferred, no
            # problem, risk or plan, no word awaited, no picture, no issue
            # (returned, stalled, ready and not sent: the card's RAID line
            # must show it), and nothing the user sent on it waiting to be
            # filed (READING).
            def self.quiet?(piece, reading)
                QUIET.include?(piece["status"]) && piece["awaits"].empty? &&
                    untold?(piece) && Raid.issues(piece).empty? &&
                    piece.fetch("pictures", []).empty? &&
                    reading.unfiled_on(piece["id"]).empty?
            end

            # No problem, risk or plan.
            def self.untold?(piece)
                Case.fields(piece).values_at("problem", "risk", "plan")
                    .all? { Text.strip(it.to_s).empty? }
            end

            def initialize(scope, lid)
                @scope = scope
                @lid = lid
            end

            # The row of PIECE, BODY the card's contents under its head
            # and DROP its trash.
            def html(piece, body, drop)
                id = piece["id"]
                @scope.partial(
                    "ledger/flight_row",
                    { id:, lid: @lid, title: piece["title"], body:, drop:,
                      status: piece["status"], why: Why.icon(@lid, id) }
                )
            end
        end
    end
end
