# frozen_string_literal: true

# A piece that is deliberate uncommitted work (docs/journal.md, section
# 1): why, set by `piece P<n> --no-commit WHY`, cleared by an empty
# WHY. While a live piece of a ledger has it, the `uncommitted` Stop
# hook stays quiet for that ledger.

Sequel.migration do
    change do
        alter_table(:pieces) do
            add_column :no_commit, String # P, NULL or non-empty
        end
    end
end
