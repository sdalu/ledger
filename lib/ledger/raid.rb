# frozen_string_literal: true

require "ledger/render/assumption_line"

module Ledger
    # What Derive says for RAID beyond the risk a row carries: the
    # assumptions, what rests on each, and when a piece was last touched
    # (how long a stalled one has been). Mixed into Derive, which gives
    # `snapshot` and, for the time, the events (`@activity`).
    module Raid
        def assumptions = snapshot.assumptions
        def aref(assumption) = "A#{assumption[:n]}"
        def open_assumptions = assumptions.select { it[:state] == "open" }

        # The assumptions a piece rests on, in id order.
        def rests_on(piece) = resting_on(:piece_id, piece)

        # The assumptions an open or closed question rests on.
        def question_rests_on(question) = resting_on(:question_id, question)

        # The ids of what ASSUMPTION rests on (`see`), in position order;
        # of the pieces and questions resting on it (`resting`), in link
        # order; of the fact that settled it, or nil.
        def assumption_sees(assumption) = assumption_line.sees(assumption)
        def resting(assumption) = assumption_line.resting(assumption)
        def settled_by(assumption) = assumption_line.fact(assumption)

        # The open assumptions' ids, the status line's `assuming:`.
        def assuming = open_assumptions.map { aref(it) }

        # When an event last touched the piece (ms): its row, or one of
        # its rows in the piece tables.
        def touched_at(piece)
            raise ArgumentError, "the times need the events" unless @activity

            @activity.touched[piece[:id]]
        end

        private

        def assumption_line
            @assumption_line ||= Render::AssumptionLine.new(snapshot)
        end

        def resting_on(column, owner)
            ids = snapshot.assumption_links.select { it[column] == owner[:id] }
                          .map { it[:assumption_id] }
            assumptions.select { ids.include?(it[:id]) }
        end
    end
end
