# frozen_string_literal: true

# A piece whose step cannot be taken back (docs/journal.md, section 1):
# set by `piece P<n> --irreversible`, cleared by `--no-irreversible`. It
# adds 3 to the step risk of each word the piece awaits.

Sequel.migration do
    change do
        alter_table(:pieces) do
            add_column :irreversible, TrueClass, null: false, default: false
        end
    end
end
