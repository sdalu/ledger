# frozen_string_literal: true

# The journal's tables (docs/journal.md, section 1): every ledger, its
# items, its events and the counters. A migration is a table of
# columns, not logic (.rubocop.local.yml lifts the block length here).

# The lists the CHECK constraints name, as SQL. Locals, not constants:
# the migrator loads this file at the top level, and the blocks below
# close over them.
sql_list = ->(words) { words.map { "'#{it}'" }.join(",") }
marks = sql_list.call([" ", "x", "-"])
statuses = sql_list.call(%w[planned out back verified blocked dropped kept])
models = sql_list.call(%w[haiku sonnet opus fable])
efforts = sql_list.call(%w[low medium high xhigh max])
awaits = sql_list.call(%w[start commit deploy push merge other])
kinds = sql_list.call(%w[P O D C F N X])
# The content types a mockup file may carry: the viewer's served list.
types = sql_list.call(["text/html; charset=utf-8", "text/css; charset=utf-8",
                       "text/javascript; charset=utf-8", "application/json",
                       "text/plain; charset=utf-8", "image/svg+xml",
                       "image/png", "image/jpeg", "image/gif", "image/webp",
                       "font/woff", "font/woff2", "font/ttf"])

Sequel.migration do
    change do
        create_table(:ledgers) do
            primary_key :id
            String :place, null: false # absolute dir the address names
            String :name, null: false, default: "" # "" or "x", LEDGER-x
            String :project, null: false # project_name(), self-routed
            Bignum :created_at, null: false # ms since the epoch
            Bignum :closed_at
            String :beat_line            # the stall counter, was PATH.beat
            Integer :beat_count, null: false, default: 0
            index %i[place name], unique: true, where: { closed_at: nil }
        end
        create_table(:counters) do       # U3: the last n given, per kind
            foreign_key :ledger_id, :ledgers, null: false
            String :kind, null: false    # P O D C F N X
            Integer :last, null: false, default: 0
            primary_key %i[ledger_id kind]
            constraint :counters_kind, "kind IN (#{kinds})"
        end
        create_table(:events) do         # U1: the write path
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Bignum :at, null: false
            String :actor, null: false   # session:<id> cli viewer:<u> import
            String :command, null: false # piece, ask, take, undo, inbox, …
            String :argv, null: false    # JSON array, as given
            String :summary              # the line the command printed
            foreign_key :undoes, :events # undo: the event; restore: the target
            index %i[ledger_id id]
        end
        create_table(:event_rows) do     # what one event changed
            foreign_key :event_id, :events, null: false
            String :tbl, null: false
            Integer :row_id, null: false
            String :before               # JSON row; nil: inserted
            String :after                # JSON row; nil: deleted
            index %i[tbl row_id]
        end
        create_table(:goals) do
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            String :stamp, null: false   # P, inside the label's "(…)"
            String :date, null: false    # YYYY-MM-DD, from the stamp
            TrueClass :revised, null: false
            String :title                # P; NULL or non-empty
            String :short                # P; NULL or non-empty
            String :context              # P; NULL or non-empty
            String :quote, null: false   # V; lines without "> ", non-empty
            constraint :goals_quote, "quote <> ''"
            constraint :goals_stamp, "stamp NOT LIKE '(%'"
            constraint :goals_title, "title IS NULL OR title <> ''"
            constraint :goals_short, "short IS NULL OR short <> ''"
            constraint :goals_context, "context IS NULL OR context <> ''"
        end
        create_table(:criteria) do       # Done when
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false
            String :mark, null: false    # " " | "x" | "-"
            String :text, null: false    # P
            String :evidence             # P; "" = an empty "— evidence:"
            String :why                  # P
            unique %i[ledger_id n]
            constraint :criteria_mark, "mark IN (#{marks})"
            constraint :criteria_one_reason,
                       "evidence IS NULL OR why IS NULL"
        end
        create_table(:constraints) do
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false
            String :text, null: false    # V: the line after "C<n>: "
            String :quote, null: false   # V: the words a brief must carry
            unique %i[ledger_id n]
        end
        create_table(:facts) do
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false
            String :text, null: false    # P
            String :pointer, null: false # P, non-empty
            unique %i[ledger_id n]
            constraint :facts_pointer, "pointer <> ''"
        end
        create_table(:decisions) do
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false      # X<n>, not printed in the Markdown
            String :date, null: false
            String :body, null: false    # V when by user (quotes the user)
            String :by, null: false      # "user" | "me"
            String :note                 # P, the "(…)" after by
            String :subject              # "O3" when the body opens "O3:"
            unique %i[ledger_id n]
            constraint :decisions_by, "by IN ('user','me')"
            constraint :decisions_date, "date LIKE '____-__-__'"
        end
        create_table(:links) do          # Links and view: X and O edges
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            String :kind, null: false    # answers replaces rests_on led_to
            String :from_kind, null: false   # X | O
            Integer :from_row, null: false   # row id in that kind's table
            String :to_kind, null: false     # O X F C P
            Integer :to_row, null: false     # row id in that kind's table
            foreign_key :event_id, :events, null: false
            index %i[ledger_id from_kind from_row]
            index %i[ledger_id to_kind to_row]
            constraint :links_ends, <<~SQL
                (kind = 'answers' AND from_kind = 'X' AND to_kind = 'O')
                OR (kind = 'replaces' AND from_kind = to_kind
                    AND from_kind IN ('X','O'))
                OR (kind = 'rests_on' AND from_kind = 'X'
                    AND to_kind IN ('F','C'))
                OR (kind = 'led_to' AND from_kind = 'X'
                    AND to_kind IN ('P','O'))
            SQL
        end
        create_table(:pieces) do
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false
            String :status, null: false  # U2: the seven stored states
            String :kept_reason          # P, non-empty iff kept
            String :model                # haiku sonnet opus fable
            String :effort               # low medium high xhigh max
            String :skills               # "c, ruby"
            String :peer                 # peer: SESSION
            TrueClass :dash, null: false # an unrouted line wrote "— "
            String :title, null: false   # P
            String :detail               # P
            String :done_when            # P; NULL or non-empty
            String :evidence             # P
            String :problem              # P
            String :risk                 # P, "7/10 — …" as written
            Integer :risk_rating         # 0..10, split out at write
            String :plan                 # P
            String :after_tail           # P, prose after the after: ids
            String :for_tail             # P, prose after the for: ids
            String :verified_by          # U11: "me", a route, peer: X
            String :claimed_by           # U12: session id while out
            unique %i[ledger_id n]
            index %i[ledger_id status]
            constraint :pieces_status, "status IN (#{statuses})"
            constraint :pieces_route, <<~SQL
                (status = 'kept' AND kept_reason IS NOT NULL
                    AND kept_reason <> '' AND model IS NULL
                    AND effort IS NULL AND peer IS NULL)
                OR (status <> 'kept' AND kept_reason IS NULL
                    AND ((model IS NOT NULL AND effort IS NOT NULL
                          AND peer IS NULL)
                         OR (peer IS NOT NULL AND model IS NULL
                             AND effort IS NULL)))
            SQL
            constraint :pieces_model, "model IS NULL OR model IN (#{models})"
            constraint :pieces_effort,
                       "effort IS NULL OR effort IN (#{efforts})"
            constraint :pieces_done_when,
                       "done_when IS NULL OR done_when <> ''"
            constraint :pieces_evidence, <<~SQL
                status <> 'verified'
                OR (evidence IS NOT NULL AND evidence <> '')
            SQL
            constraint :pieces_risk_rating,
                       "risk_rating BETWEEN 0 AND 10"
            constraint :pieces_verified_by,
                       "status <> 'verified' OR verified_by IS NOT NULL"
            constraint :pieces_claim, "claimed_by IS NULL OR status = 'out'"
            constraint :pieces_claimed,
                       "status <> 'out' OR claimed_by IS NOT NULL"
        end
        create_table(:piece_links) do    # — after: / — for:
            primary_key :id
            foreign_key :piece_id, :pieces, null: false
            String :kind, null: false    # "after" | "for"
            Integer :position, null: false
            foreign_key :after_id, :pieces
            foreign_key :criterion_id, :criteria
            constraint :piece_links_target, <<~SQL
                (kind = 'after' AND after_id IS NOT NULL
                    AND after_id <> piece_id AND criterion_id IS NULL)
                OR (kind = 'for' AND criterion_id IS NOT NULL
                    AND after_id IS NULL)
            SQL
        end
        create_table(:piece_awaits) do   # — awaits: one row per word
            primary_key :id
            foreign_key :piece_id, :pieces, null: false
            Integer :position, null: false
            String :word, null: false    # start commit deploy push merge other
            String :what                 # P, other's "(…)"
            constraint :piece_awaits_word, "word IN (#{awaits})"
            constraint :piece_awaits_what, <<~SQL
                (word = 'other' AND what IS NOT NULL AND what <> '')
                OR (word <> 'other' AND what IS NULL)
            SQL
        end
        create_table(:piece_scopes) do   # — scope: WORD = what | …
            primary_key :id
            foreign_key :piece_id, :pieces, null: false
            Integer :position, null: false
            String :word, null: false
            String :text, null: false    # P
        end
        create_table(:piece_briefs) do   # U10, schema now
            primary_key :id
            foreign_key :piece_id, :pieces, null: false
            Integer :version, null: false
            String :text, null: false    # P, the brief as sent
            foreign_key :event_id, :events, null: false
        end
        create_table(:piece_criteria) do # U16, schema now
            primary_key :id
            foreign_key :piece_id, :pieces, null: false
            Integer :position, null: false
            String :text, null: false    # P
            String :mark, null: false    # " " | "x" | "-"
            String :evidence             # P
            constraint :piece_criteria_mark, "mark IN (#{marks})"
        end
        create_table(:questions) do      # Open
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false
            String :title, null: false   # P
            String :detail, null: false  # P, the question sentence
            String :problem              # P
            String :risk                 # P, as written
            Integer :risk_rating
            String :recommend            # P
            foreign_key :by_id, :pieces  # — by: P<n>
            String :no_picture           # P, --no-picture's why (not shown)
            String :tail                 # P, prose after a link's ids
            Bignum :closed_at            # NULL while under Open
            unique %i[ledger_id n]
            index %i[ledger_id closed_at]
            constraint :questions_risk_rating,
                       "risk_rating BETWEEN 0 AND 10"
        end
        create_table(:question_choices) do
            primary_key :id
            foreign_key :question_id, :questions, null: false
            Integer :position, null: false
            String :label, null: false   # P
            String :effect               # P
            String :cost                 # P
        end
        create_table(:question_items) do # — items: a | b
            primary_key :id
            foreign_key :question_id, :questions, null: false
            Integer :position, null: false
            String :text, null: false    # P
        end
        create_table(:question_sees) do  # — see: F2, C3
            primary_key :id
            foreign_key :question_id, :questions, null: false
            Integer :position, null: false
            foreign_key :constraint_id, :constraints
            foreign_key :criterion_id, :criteria
            foreign_key :fact_id, :facts
            foreign_key :piece_id, :pieces
            constraint :question_sees_one_target, <<~SQL
                (constraint_id IS NOT NULL) + (criterion_id IS NOT NULL)
                + (fact_id IS NOT NULL) + (piece_id IS NOT NULL) = 1
            SQL
        end
        create_table(:pictures) do       # S1: a mockup's files, as blobs
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            String :name, null: false    # the mockup's name (`mockup: NAME`)
            String :path, null: false    # "" for one file; else its path
            String :type, null: false    # the served content type
            File :bytes, null: false     # the file, byte for byte
            foreign_key :event_id, :events, null: false # the mockup command
            unique %i[ledger_id name path]
            constraint :pictures_name, "name <> ''"
            constraint :pictures_type, "type IN (#{types})"
        end
        create_table(:question_pictures) do # — mockup: NAME | pending (P<n>)
            primary_key :id
            foreign_key :question_id, :questions, null: false
            Integer :position, null: false
            String :name                 # a pictures.name of this ledger
            foreign_key :pending_id, :pieces
            constraint :question_pictures_one_target,
                       "(name IS NOT NULL) + (pending_id IS NOT NULL) = 1"
        end
        create_table(:noticed) do        # Out of scope, noticed
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            String :line, null: false    # P, the whole line verbatim
        end
        create_table(:inbox_entries) do  # was PATH.inbox
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false      # N<n>, a malformed line's too
            String :at, null: false      # the viewer's "YYYY-MM-DD HH:MM:SS"
            String :ref                  # O3, P4, "order", NULL: not a key
            String :payload, null: false # V: the JSON object as written
            TrueClass :malformed, null: false, default: false
            foreign_key :taken_id, :events # the take; was .inbox.taken
            unique %i[ledger_id n]
        end
    end
end
