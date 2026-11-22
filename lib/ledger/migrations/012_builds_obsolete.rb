# frozen_string_literal: true

# A piece that builds a question, and a piece made obsolete by another
# (docs/journal.md, section 1). `builds_id`: the question the piece
# builds (`piece --builds O<n>`), one piece at most per question.
# `obsoleted_by_id`: the piece that replaces it, set with the status
# 'obsolete' and only with it. The status CHECK gains 'obsolete', which
# SQLite changes only by rebuilding the table: as in 004, every CHECK
# is given again, outside a migration transaction so that Sequel can
# turn the foreign keys off around the rebuild.

sql_list = ->(words) { words.map { "'#{it}'" }.join(",") }
statuses = sql_list.call(%w[planned out back verified blocked dropped kept
                            deferred obsolete])
models = sql_list.call(%w[haiku sonnet opus fable])
efforts = sql_list.call(%w[low medium high xhigh max])

Sequel.migration do
    no_transaction

    up do
        alter_table(:pieces) do
            add_foreign_key :builds_id, :questions # P --builds O<n>
            add_foreign_key :obsoleted_by_id, :pieces # P --obsoleted-by
        end
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
            add_constraint :pieces_obsolete, <<~SQL
                (status = 'obsolete') = (obsoleted_by_id IS NOT NULL)
            SQL
        end
        # Apart: an index in the block above would split the rebuild,
        # and each part keeps only the CHECKs it adds.
        add_index :pieces, :builds_id, unique: true
    end
end
