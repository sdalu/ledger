# frozen_string_literal: true

# A piece's pictures (docs/journal.md, section 1): the before and the
# after of what a piece awaiting the user's word changes, each a name
# of the ledger's pictures; and, for a piece that has none, why.

Sequel.migration do
    change do
        create_table(:piece_pictures) do # mockup --piece P<n> --before|--after
            primary_key :id
            foreign_key :piece_id, :pieces, null: false
            Integer :position, null: false
            String :role, null: false    # before | after
            String :name, null: false    # a pictures.name of this ledger
            index :piece_id
            constraint :piece_pictures_role, "role IN ('before','after')"
        end
        alter_table(:pieces) do
            add_column :no_picture, String # P, --no-picture's why
        end
    end
end
