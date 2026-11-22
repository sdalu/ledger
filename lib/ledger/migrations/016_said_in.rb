# frozen_string_literal: true

# Where the user said a quote that this session's transcript does not
# hold (docs/journal.md, section 1): `--said-in WHERE` on `new --goal`,
# `goal --quote` and `constraint`, NULL when the transcript holds the
# quote or no place was given.

Sequel.migration do
    change do
        alter_table(:goals) do
            add_column :said_in, String # P, NULL or non-empty
        end
        alter_table(:constraints) do
            add_column :said_in, String # P, NULL or non-empty
        end
    end
end
