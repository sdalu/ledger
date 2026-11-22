# frozen_string_literal: true

# An option's own picture (docs/journal.md, section 1): the name of one
# of the ledger's pictures, set by `mockup PATH FILE --question O<n>
# --choice LABEL`; it goes with the option when the option is dropped.

Sequel.migration do
    change do
        alter_table(:question_choices) do
            add_column :picture, String # a pictures.name of this ledger
        end
    end
end
