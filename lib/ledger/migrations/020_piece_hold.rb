# frozen_string_literal: true

# A planned piece held on purpose (docs/journal.md, section 1): why, set
# by `piece P<n> --hold WHY`, cleared by an empty WHY, by any status but
# planned, and (derived, nothing written) when every piece the why names
# has settled.

Sequel.migration do
    change do
        alter_table(:pieces) do
            add_column :hold, String # P, NULL or non-empty
        end
    end
end
