# frozen_string_literal: true

# The waker (docs/journal.md, section 8): the sessions the session-start
# hook saw, the ledgers of each one's directory, each one's last turn end
# (the stamp hook), the per-ledger switch, and every wake the waker made.
# The messaging token is never stored: the socket takes a line without it.

sql_list = ->(words) { words.map { "'#{it}'" }.join(",") }
paths = sql_list.call(%w[socket resume])

Sequel.migration do
    change do
        create_table(:sessions) do       # session-start, per session
            String :session_id, primary_key: true
            String :socket               # CLAUDE_CODE_MESSAGING_SOCKET
            String :cwd, null: false     # where claude --resume runs
            Bignum :at, null: false      # when session-start recorded it
        end
        create_table(:session_ledgers) do # the ledgers of its directory
            foreign_key :session_id, :sessions, type: String, null: false,
                                                on_update: :cascade
            foreign_key :ledger_id, :ledgers, null: false
            primary_key %i[session_id ledger_id]
        end
        create_table(:session_stops) do  # the stamp hook: the last turn end
            String :session_id, primary_key: true
            Bignum :at, null: false
        end
        alter_table(:ledgers) do         # ledger waker PATH on|off
            add_column :waker, TrueClass, null: false, default: false
        end
        create_table(:wakes) do          # every wake, as it went
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            String :session_id, null: false
            Bignum :at, null: false
            String :path, null: false    # socket | resume
            String :outcome, null: false # posted, resumed, copied ID, …
            index %i[ledger_id at]
            constraint :wakes_path, "path IN (#{paths})"
        end
    end
end
