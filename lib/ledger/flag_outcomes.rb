# frozen_string_literal: true

require "ledger/checks/fresh"
require "ledger/outcomes"

module Ledger
    # The flags a check shows on each piece (unsent, stalled,
    # pictures-fresh) recorded in outcomes when they move: flag_on when
    # one appears on a piece, flag_off when it clears. A piece's last
    # state for a flag is the last such row; none yet is off. A piece
    # whose picture is being redrawn is not stale, as a plain check says.
    #
    #     Ledger::FlagOutcomes.new(db, derive).record(err: $stderr)
    class FlagOutcomes
        KINDS = %w[flag_on flag_off].freeze

        def initialize(db, derive)
            @db = db
            @derive = derive
        end

        def record(err:) = Outcomes.write(rows, err:)

        # The rows of the flags that moved since the last recorded.
        def rows
            last = recorded
            current.filter_map do |(ref, flag), on|
                next if on == last.fetch([ref, flag], false)

                { kind: on ? "flag_on" : "flag_off", rule: flag, ref:,
                  ledger_id: }
            end
        end

        private

        def ledger_id = @derive.snapshot.ledger_id

        # {[ref, flag] => shown} of every piece and flag.
        def current
            @derive.pieces.each_with_object({}) do |piece, flags|
                ref = @derive.ref(piece)
                shown(piece).each { |flag, on| flags[[ref, flag]] = on }
            end
        end

        def shown(piece)
            { "unsent" => @derive.unsent?(piece),
              "stalled" => @derive.stalled?(piece),
              "pictures-fresh" => stale?(piece) }
        end

        def stale?(piece)
            !Checks::Fresh.pending?(@derive, piece) &&
                !Checks::Fresh.piece_line(@derive, piece).nil?
        end

        # {[ref, flag] => on} as the last rows say.
        def recorded
            @db[:outcomes].where(ledger_id:, kind: KINDS).order(:id)
                          .select_map(%i[ref rule kind])
                          .to_h do |ref, rule, kind|
                              [[ref, rule], kind == KINDS.first]
                          end
        end
    end
end
