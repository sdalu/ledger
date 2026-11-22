# frozen_string_literal: true

require "ledger/text/paths"

module Ledger
    # The facts that bear on one piece: those whose pointer names a path
    # the piece's detail or plan names (the same path, or one under a
    # directory the other names), and those linked to it: a fact a
    # decision that led to the piece rests on, a fact an assumption the
    # piece rests on sees or was settled by, a fact a question the piece
    # builds or draws (`--by`) sees.
    #
    #     Ledger::PieceFacts.new(db, ledger_id, piece_row).facts
    #     # => [{id: "F2", text: "...", pointer: "lib/x.rb:12"}]
    class PieceFacts
        def initialize(db, ledger_id, piece)
            @db = db
            @ledger_id = ledger_id
            @piece = piece
        end

        def facts
            ids = linked
            named = Text::Paths.scan("#{@piece[:detail]}\n#{@piece[:plan]}")
            rows = @db[:facts].where(ledger_id: @ledger_id).order(:n).all
            rows.select { ids.include?(it[:id]) || pointed?(it, named) }
                .map { entry(it) }
        end

        private

        def entry(fact)
            { id: "F#{fact[:n]}", text: fact[:text], pointer: fact[:pointer] }
        end

        def pointed?(fact, named)
            Text::Paths.scan(fact[:pointer]).any? do |path|
                Text::Paths.covered?(path, named) ||
                    named.any? { Text::Paths.covered?(it, [path]) }
            end
        end

        # The row ids of the facts linked to the piece.
        def linked
            (decided + assumed + asked).to_set
        end

        def decided
            led = @db[:links].where(ledger_id: @ledger_id, kind: "led_to",
                                    to_kind: "P", to_row: @piece[:id])
                             .select(:from_row)
            @db[:links].where(ledger_id: @ledger_id, kind: "rests_on",
                              from_kind: "X", from_row: led, to_kind: "F")
                       .select_map(:to_row)
        end

        def assumed
            ids = @db[:assumption_links].where(piece_id: @piece[:id])
                                        .select(:assumption_id)
            @db[:assumption_sees].where(assumption_id: ids)
                                 .exclude(fact_id: nil).select_map(:fact_id) +
                @db[:assumptions].where(id: ids).exclude(fact_id: nil)
                                 .select_map(:fact_id)
        end

        def asked
            ids = @db[:questions].where(ledger_id: @ledger_id)
                                 .where(Sequel.|({ id: @piece[:builds_id] },
                                                 { by_id: @piece[:id] }))
                                 .select(:id)
            @db[:question_sees].where(question_id: ids).exclude(fact_id: nil)
                               .select_map(:fact_id)
        end
    end
end
