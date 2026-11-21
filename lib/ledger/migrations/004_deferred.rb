# frozen_string_literal: true

# A deferred piece (docs/journal.md, section 1): not done, waiting on a
# future event that is not the user, the event in `until`. The status
# CHECK gains 'deferred'. SQLite changes a CHECK only by rebuilding the
# table, which Sequel's alter_table does (columns, unique, indexes and
# foreign keys carried over) but with only the CHECKs it is given: so
# every CHECK of 001 is given again, the status one with 'deferred'.
# The rebuild runs outside a migration transaction, so that Sequel can
# turn the foreign keys off around it: the tables referencing pieces
# keep naming pieces.

sql_list = ->(words) { words.map { "'#{it}'" }.join(",") }
statuses = sql_list.call(%w[planned out back verified blocked dropped kept
                            deferred])
models = sql_list.call(%w[haiku sonnet opus fable])
efforts = sql_list.call(%w[low medium high xhigh max])

Sequel.migration do
    no_transaction

    up do
        # P: the event a deferred piece waits on.
        alter_table(:pieces) { add_column :until, String }
        alter_table(:pieces) do
            add_constraint :pieces_status, "status IN (#{statuses})"
            add_constraint :pieces_route, <<~SQL
                (status = 'kept' AND kept_reason IS NOT NULL
                    AND kept_reason <> '' AND model IS NULL
                    AND effort IS NULL AND peer IS NULL)
                OR (status <> 'kept' AND kept_reason IS NULL
                    AND ((model IS NOT NULL AND effort IS NOT NULL
                          AND peer IS NULL)
                         OR (peer IS NOT NULL AND model IS NULL
                             AND effort IS NULL)))
            SQL
            add_constraint :pieces_model,
                           "model IS NULL OR model IN (#{models})"
            add_constraint :pieces_effort,
                           "effort IS NULL OR effort IN (#{efforts})"
            add_constraint :pieces_done_when,
                           "done_when IS NULL OR done_when <> ''"
            add_constraint :pieces_evidence, <<~SQL
                status <> 'verified'
                OR (evidence IS NOT NULL AND evidence <> '')
            SQL
            add_constraint :pieces_risk_rating, "risk_rating BETWEEN 0 AND 10"
            add_constraint :pieces_verified_by,
                           "status <> 'verified' OR verified_by IS NOT NULL"
            add_constraint :pieces_claim, "claimed_by IS NULL OR status = 'out'"
            add_constraint :pieces_claimed,
                           "status <> 'out' OR claimed_by IS NOT NULL"
        end
    end
end
