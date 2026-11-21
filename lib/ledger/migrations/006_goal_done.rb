# frozen_string_literal: true

# A Goal block's id and its done mark (docs/journal.md, section 1):
# `G<n>`, given by the counter like every other id, the blocks already
# written numbered in id order; `done_at` and `done_evidence`, set
# together by `goal PATH G<n> --done`, cleared together by `--undone`.

sql_list = ->(words) { words.map { "'#{it}'" }.join(",") }
kinds = sql_list.call(%w[P O D C F N X G])

Sequel.migration do
    up do
        # goals is built again: SQLite adds a NOT NULL column or a CHECK
        # to a table only by copying it.
        rename_table(:goals, :goals_before_g)
        create_table(:goals) do
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false      # G<n>
            String :stamp, null: false   # P, inside the label's "(…)"
            String :date, null: false    # YYYY-MM-DD, from the stamp
            TrueClass :revised, null: false
            String :title                # P; NULL or non-empty
            String :short                # P; NULL or non-empty
            String :context              # P; NULL or non-empty
            String :quote, null: false   # V; lines without "> ", non-empty
            Bignum :done_at              # ms; NULL while the goal is active
            String :done_evidence        # P; set exactly while done
            unique %i[ledger_id n]
            constraint :goals_quote, "quote <> ''"
            constraint :goals_stamp, "stamp NOT LIKE '(%'"
            constraint :goals_title, "title IS NULL OR title <> ''"
            constraint :goals_short, "short IS NULL OR short <> ''"
            constraint :goals_context, "context IS NULL OR context <> ''"
            constraint :goals_done,
                       "(done_at IS NULL) = (done_evidence IS NULL)"
            constraint :goals_done_evidence,
                       "done_evidence IS NULL OR done_evidence <> ''"
        end
        run <<~SQL
            INSERT INTO goals (id, ledger_id, n, stamp, date, revised, title,
                               short, context, quote)
            SELECT id, ledger_id,
                   ROW_NUMBER() OVER (PARTITION BY ledger_id ORDER BY id),
                   stamp, date, revised, title, short, context, quote
            FROM goals_before_g
        SQL
        drop_table(:goals_before_g)

        # G joins the counted kinds, each ledger's counter at its blocks.
        alter_table(:counters) do
            drop_constraint :counters_kind
            add_constraint :counters_kind, "kind IN (#{kinds})"
        end
        run <<~SQL
            INSERT INTO counters (ledger_id, kind, last)
            SELECT id, 'G',
                   (SELECT COUNT(*) FROM goals WHERE ledger_id = ledgers.id)
            FROM ledgers
        SQL
    end
end
