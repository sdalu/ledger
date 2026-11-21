# frozen_string_literal: true

# A piece's returns (docs/journal.md, section 1): each time a piece out
# or back goes back to planned, the cause, the status it left and the
# event that wrote it (its time and actor).

sql_list = ->(words) { words.map { "'#{it}'" }.join(",") }
froms = sql_list.call(%w[out back])
causes = sql_list.call(%w[brief split depth contract env])

Sequel.migration do
    change do
        create_table(:piece_returns) do # piece --status planned --cause
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            foreign_key :piece_id, :pieces, null: false
            foreign_key :event_id, :events, null: false # the return's write
            String :from_status, null: false # out | back
            String :cause, null: false # brief split depth contract env
            index %i[ledger_id piece_id]
            constraint :piece_returns_from, "from_status IN (#{froms})"
            constraint :piece_returns_cause, "cause IN (#{causes})"
        end
    end
end
