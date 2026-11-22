# frozen_string_literal: true

# A piece's gates and its helper's report (docs/journal.md, section 1).
# `piece P<n> --gate "NAME: STATE (DETAIL)"` keeps one row per NAME, a
# later state replacing it, its time the event that last wrote it.
# `piece P<n> --report FILE` keeps one report per piece, a later one
# replacing it: the first line, the status word, and up to 12 lines
# after it.

sql_list = ->(words) { words.map { "'#{it}'" }.join(",") }
states = sql_list.call(%w[queued running passed failed])

Sequel.migration do
    change do
        create_table(:piece_gates) do # piece --gate "NAME: STATE (DETAIL)"
            primary_key :id
            foreign_key :piece_id, :pieces, null: false
            foreign_key :event_id, :events, null: false # the last write
            String :name, null: false
            String :state, null: false # queued running passed failed
            String :detail             # NULL or non-empty
            unique %i[piece_id name]
            constraint :piece_gates_state, "state IN (#{states})"
            constraint :piece_gates_name, "name <> ''"
            constraint :piece_gates_detail, "detail IS NULL OR detail <> ''"
        end
        create_table(:piece_reports) do # piece --report FILE
            primary_key :id
            foreign_key :piece_id, :pieces, null: false, unique: true
            foreign_key :event_id, :events, null: false # the last write
            String :status, null: false # the first line
            String :body                # up to 12 lines after it, or NULL
            constraint :piece_reports_status, "status <> ''"
        end
    end
end
