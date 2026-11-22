# frozen_string_literal: true

require "ledger/checks/fresh"
require "ledger/outcomes"

module Ledger
    # The flags a check shows on each piece (unsent, stalled,
    # pictures-fresh) and on each open question (pictures-fresh)
    # recorded in outcomes when they move: flag_on when one appears on an
    # item, flag_off when it clears. An item's last state for a flag is
    # the last such row; none yet is off. A piece whose picture is being
    # redrawn is not stale, as a plain check says.
    #
    #     Ledger::FlagOutcomes.new(db, derive).record(err: $stderr)
    class FlagOutcomes
        KINDS = %w[flag_on flag_off].freeze
        FRESH = "pictures-fresh"

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

        # {[ref, flag] => shown} of every piece and flag, and of every
        # question's picture (stale only while the question is open).
        def current
            flags = @derive.pieces.each_with_object({}) do |piece, all|
                ref = @derive.ref(piece)
                shown(piece).each { |flag, on| all[[ref, flag]] = on }
            end
            @derive.snapshot.questions.each do |question|
                ref = @derive.qref(question)
                flags[[ref, FRESH]] = stale_question?(question)
            end
            flags
        end

        def stale_question?(question)
            question[:closed_at].nil? &&
                !Checks::Fresh.question_line(@derive, question).nil?
        end

        def shown(piece)
            { "unsent" => @derive.unsent?(piece),
              "stalled" => @derive.stalled?(piece),
              FRESH => stale?(piece) }
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
