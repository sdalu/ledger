# frozen_string_literal: true

# A dispatch's assessment (docs/journal.md, section 1): the ANNOUNCE
# block `piece PATH P<n> --announce FILE` reads, one row per call, so a
# retry or a fan-out under one brief is a row each. Its time and actor
# are those of the event that wrote it; `session` is the dispatching
# session when it is known.

sql_list = ->(words) { words.map { "'#{it}'" }.join(",") }
levels = sql_list.call(%w[low mid high])

Sequel.migration do
    change do
        create_table(:piece_assessments) do # piece --announce FILE
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            foreign_key :piece_id, :pieces, null: false
            foreign_key :event_id, :events, null: false # the write
            String :session                 # who dispatched, when known
            String :what, null: false       # WHAT
            String :why, null: false        # WHY, raw
            String :model, null: false      # WHICH: the model named
            String :effort                  # WHICH: effort, when given
            String :axis                    # WHICH: highest axis, lower-cased
            String :axis_level              # low | mid | high
            Integer :risk_rating            # RISK: N of N/10, NULL unrated
            String :risk_text, null: false  # RISK, whole
            String :mode, null: false       # MODE, raw
            # Whether MODE's first word is attended.
            TrueClass :mode_attended, null: false
            String :block, null: false # the block as read
            index %i[ledger_id piece_id]
            constraint :piece_assessments_level,
                       "axis_level IS NULL OR axis_level IN (#{levels})"
            constraint :piece_assessments_rating,
                       "risk_rating IS NULL OR risk_rating BETWEEN 0 AND 10"
        end
    end
end
