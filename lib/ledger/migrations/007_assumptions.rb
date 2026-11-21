# frozen_string_literal: true

# Assumptions (docs/journal.md, section 1): what the plan takes as true
# without having checked it, `A<n>`, with how it will be checked, open
# until a fact of the ledger confirms or refutes it (`fact_id`, NULL
# while open); the items it rests on (`— see:`) and the pieces and
# questions resting on it (`— for:`). The counters' kind CHECK gains
# 'A', each ledger an A counter at 0.

sql_list = ->(words) { words.map { "'#{it}'" }.join(",") }
kinds = sql_list.call(%w[P O D C F N X G A])
states = sql_list.call(%w[open confirmed refuted])

Sequel.migration do
    up do
        create_table(:assumptions) do
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false      # A<n>
            String :text, null: false    # P, what is taken as true
            String :check, null: false   # P, how it will be checked
            String :state, null: false   # open | confirmed | refuted
            foreign_key :fact_id, :facts # the fact that settled it
            unique %i[ledger_id n]
            constraint :assumptions_text, "text <> ''"
            constraint :assumptions_check, "\"check\" <> ''"
            constraint :assumptions_state, "state IN (#{states})"
            constraint :assumptions_open,
                       "state <> 'open' OR fact_id IS NULL"
        end
        create_table(:assumption_sees) do  # — see: F2, C1
            primary_key :id
            foreign_key :assumption_id, :assumptions, null: false
            Integer :position, null: false
            foreign_key :constraint_id, :constraints
            foreign_key :criterion_id, :criteria
            foreign_key :fact_id, :facts
            foreign_key :piece_id, :pieces
            index :assumption_id
            constraint :assumption_sees_one_target, <<~SQL
                (constraint_id IS NOT NULL) + (criterion_id IS NOT NULL)
                + (fact_id IS NOT NULL) + (piece_id IS NOT NULL) = 1
            SQL
        end
        create_table(:assumption_links) do # — for: P3, O2
            primary_key :id
            foreign_key :assumption_id, :assumptions, null: false
            foreign_key :piece_id, :pieces
            foreign_key :question_id, :questions
            index :assumption_id
            constraint :assumption_links_one_target,
                       "(piece_id IS NOT NULL) + (question_id IS NOT NULL) = 1"
        end

        # A joins the counted kinds, each ledger's counter at 0.
        alter_table(:counters) do
            drop_constraint :counters_kind
            add_constraint :counters_kind, "kind IN (#{kinds})"
        end
        run <<~SQL
            INSERT INTO counters (ledger_id, kind, last)
            SELECT id, 'A', 0 FROM ledgers
        SQL
    end
end
