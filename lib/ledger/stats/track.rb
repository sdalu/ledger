# frozen_string_literal: true

module Ledger
    class Stats
        # One piece read through its status changes (Stats::Change, oldest
        # first) and its piece_returns rows ([piece_id, event_id, cause]).
        class Track
            # The statuses a return leaves for planned.
            RETURNED = %w[out back].freeze

            # The pieces row read.
            attr_reader :piece

            def initialize(piece, changes, recorded)
                @piece = piece
                @changes = changes
                @recorded = recorded
            end

            def verified? = @piece[:status] == "verified"
            def first_pass? = verified? && returns.empty?

            def blocked?
                @piece[:status] == "blocked" ||
                    @changes.any? { it.to == "blocked" }
            end

            # Each span out in ms: from a change to out to the next change
            # of status; a piece still out has no span for it.
            def spans
                @changes.each_cons(2).filter_map do |out, after|
                    after.at - out.at if out.to == "out"
                end
            end

            # The cause of each return: the piece_returns rows, and
            # `unrecorded` for a return with none.
            def causes = caused.map(&:last)

            # [event_id, cause] of each return, as #causes counts them.
            def caused
                events = @recorded.map { it[1] }
                unrecorded = returns.reject { events.include?(it.event_id) }
                @recorded.map { it.drop(1) } +
                    unrecorded.map { [it.event_id, UNRECORDED] }
            end

            private

            # The changes from out or back to planned.
            def returns
                @changes.select do |change|
                    RETURNED.include?(change.from) && change.to == "planned"
                end
            end
        end
    end
end
