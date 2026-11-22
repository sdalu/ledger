# frozen_string_literal: true

# The session whose check last beat (docs/journal.md, section 1): the
# owner of the stall counter, NULL until an owner's check stores it.

Sequel.migration do
    change do
        alter_table(:ledgers) do
            add_column :beat_session, String # P, NULL or a session id
        end
    end
end
