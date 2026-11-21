# frozen_string_literal: true

require "ledger/history"

module Ledger
    class Stats
        # The events of some ledgers that are no longer in force: every
        # undo and restore itself, and every event one of them reverted
        # (History: an undo reverts the event it `undoes`, a restore every
        # item-changing event after its target). A revert that a later
        # one reverted reverts nothing any more, so the reverts are read
        # newest first.
        #
        #     Stats::InForce.new(db, [3]).reverted # => #<Set: {12, 13}>
        class InForce
            REVERTS = %w[undo restore].freeze

            def initialize(db, ledger_ids)
                @events = db[:events].where(ledger_id: ledger_ids)
                                     .select(:id, :ledger_id, :command,
                                             :undoes)
                                     .order(:id).all
            end

            # The ids of the events not in force.
            def reverted
                @events.select { REVERTS.include?(it[:command]) }
                       .reverse.each_with_object(Set[]) do |revert, out|
                    undone = out.include?(revert[:id])
                    out << revert[:id]
                    out.merge(targets(revert)) unless undone
                end
            end

            private

            def targets(revert)
                return [revert[:undoes]] if revert[:command] == "undo"

                @events.filter_map do |event|
                    event[:id] if restored?(event, revert)
                end
            end

            def restored?(event, restore)
                event[:ledger_id] == restore[:ledger_id] &&
                    event[:id].between?(restore[:undoes] + 1,
                                        restore[:id] - 1) &&
                    !History::SILENT.include?(event[:command])
            end
        end
    end
end
