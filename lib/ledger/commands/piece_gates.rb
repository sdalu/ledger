# frozen_string_literal: true

module Ledger
    module Commands
        # `piece --gate "NAME: STATE (DETAIL)"`: one gate's state on a
        # piece, STATE one of queued, running, passed, failed, DETAIL
        # optional. A piece holds one row per NAME: a later state replaces
        # the row, its event the one that wrote it last, so the row's time
        # is that of its state. Parsed before the write opens.
        class PieceGates
            STATES = %w[queued running passed failed].freeze
            FORM = /\A(?<name>[^:]*?)\s*:\s*(?<state>\S+)
                   (?:\s+\((?<detail>.*)\))?\s*\z/mx
            SHAPE = "--gate takes \"NAME: STATE (DETAIL)\", STATE one of " \
                    "#{STATES.join(", ")}, (DETAIL) optional".freeze

            def initialize(change, db, opts)
                @change = change
                @db = db
                @gate = PieceGates.parse(opts["gate"]) if opts.key?("gate")
            end

            # {name:, state:, detail:} of VALUE; Refused when it is not a
            # gate's shape.
            def self.parse(value)
                found = FORM.match(value.to_s.strip)
                raise Refused, SHAPE unless found && shaped?(found)

                detail = found[:detail]&.strip
                { name: found[:name].strip, state: found[:state],
                  detail: (detail unless detail.to_s.empty?) }
            end

            def self.shaped?(found)
                !found[:name].strip.empty? && STATES.include?(found[:state])
            end

            # Writes the gate on PIECE (a row id): a new row, or the row of
            # its name with the new state.
            def record(piece)
                return unless @gate

                held = @db[:piece_gates].where(piece_id: piece,
                                               name: @gate[:name]).get(:id)
                return @change.insert(:piece_gates, piece_id: piece, **@gate) \
                    unless held

                @change.update(:piece_gates, held,
                               event_id: @change.event_id,
                               **@gate.slice(:state, :detail))
            end
        end
    end
end
