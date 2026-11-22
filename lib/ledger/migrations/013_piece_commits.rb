# frozen_string_literal: true

# The commits that landed a piece (docs/journal.md, section 1): one row
# per abbreviated id, in the order `piece --commits` appended them. An id
# is 7 to 40 lower-case hex digits and a piece holds each once.

Sequel.migration do
    change do
        create_table(:piece_commits) do # piece --commits SHA[,SHA...]
            primary_key :id
            foreign_key :piece_id, :pieces, null: false
            Integer :position, null: false
            String :sha, null: false # 7-40 lower-case hex
            unique %i[piece_id sha]
            constraint :piece_commits_sha, <<~SQL
                length(sha) BETWEEN 7 AND 40 AND sha NOT GLOB '*[^0-9a-f]*'
            SQL
        end
    end
end
