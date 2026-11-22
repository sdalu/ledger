# frozen_string_literal: true

# A piece's picture being redrawn (docs/journal.md, section 1): why,
# set by `piece P<n> --picture-pending WHY`, cleared by the next
# `mockup --piece P<n>` or by an empty WHY. While set, pictures-fresh
# announces the piece instead of warning about it. And why a picture
# still shows its piece after a change, `piece P<n> --picture-holds
# WHY`, with the time of that write: pictures-fresh measures from then.

Sequel.migration do
    change do
        alter_table(:pieces) do
            add_column :picture_pending, String # P, NULL or non-empty
            add_column :picture_holds, String   # P, NULL or non-empty
            add_column :picture_holds_at, Integer # ms, set with holds
        end
    end
end
