# frozen_string_literal: true

# The rows an event changed, found by the event: every reader that joins
# event_rows to events for one ledger (Read, Derive, Stamps, Stats, the
# write path) would otherwise scan the whole table once per event, a
# cost that grows with the square of the journal's history. IF NOT
# EXISTS: a journal that already holds the index migrates all the same.

Sequel.migration do
    up do
        run "CREATE INDEX IF NOT EXISTS event_rows_event_id_index " \
            "ON event_rows (event_id)"
    end

    down do
        run "DROP INDEX IF EXISTS event_rows_event_id_index"
    end
end
