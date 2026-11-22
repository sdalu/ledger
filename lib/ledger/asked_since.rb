# frozen_string_literal: true

module Ledger
    # Since when an item has asked for the user's word, in epoch ms, read
    # from the events: a question since the event that asked it, a piece
    # since the newest write of one of its awaits rows (or, awaiting
    # nothing ever, since the event that added it). 0 when the events
    # say nothing: any message of the user's is then after it.
    #
    #     Ledger::AskedSince.question(db, question_row_id) # => ms
    #     Ledger::AskedSince.piece(db, piece_row_id)       # => ms
    #     Ledger::AskedSince.ref(db, ledger_id, "O3")      # => ms or nil
    module AskedSince
        TABLES = { "O" => :questions, "P" => :pieces }.freeze

        module_function

        # The ask of the question or piece REF (O<n>, P<n>) of a ledger;
        # nil when it names no such item.
        def ref(db, ledger_id, ref)
            table = TABLES[ref[0]] or return
            id = db[table].where(ledger_id:, n: ref[1..].to_i).get(:id)
            return unless id

            row(db, table, id)
        end

        # The ask of the row ID of TABLE, :questions or :pieces.
        def row(db, table, id)
            table == :pieces ? piece(db, id) : question(db, id)
        end

        def question(db, id) = inserted(db, "questions", id) || 0

        def piece(db, id)
            awaits(db, id) || inserted(db, "pieces", id) || 0
        end

        def awaits(db, id)
            owner = Sequel.lit("json_extract(after, '$.piece_id')")
            rows(db).where(tbl: "piece_awaits", before: nil)
                    .where(owner => id)
                    .max(Sequel[:events][:at])
        end

        def inserted(db, table, id)
            rows(db).where(tbl: table, row_id: id, before: nil)
                    .min(Sequel[:events][:at])
        end

        def rows(db) = db[:event_rows].join(:events, id: :event_id)
    end
end
