# frozen_string_literal: true

# What the practice did, one countable row each (docs/journal.md,
# section 1): a refusal by a writer word or a hook, a flag appearing on
# a piece or clearing, a Stop hook's verdict. Not events: undo and
# restore never touch these rows, and a purge deletes a ledger's.

Sequel.migration do
    change do
        create_table(:outcomes) do
            primary_key :id
            foreign_key :ledger_id, :ledgers # NULL when none is known
            String :session # NULL outside a session
            Integer :at, null: false # ms since the epoch
            String :kind, null: false
            String :rule, null: false # check, hook or flag name
            String :ref # P<n> or O<n>, NULL when about no item
            String :detail # the refusal's words, a verdict's why
            index %i[ledger_id kind]
            constraint :outcomes_kind,
                       kind: %w[refusal flag_on flag_off hook]
            constraint :outcomes_ref, <<~SQL
                ref IS NULL OR (ref GLOB '[PO][1-9]*' AND
                                substr(ref, 2) NOT GLOB '*[^0-9]*')
            SQL
        end
    end
end
