# frozen_string_literal: true

module Ledger
    # One ledger's rows as plain Ruby values: the ledger row and, per
    # table, its rows as hashes in id order. The shape every reader uses,
    # and the before and after of a write. Pictures come without their
    # bytes, which stay in the journal.
    class Snapshot
        # Keyed by ledger_id.
        LEDGER_TABLES = %i[goals criteria constraints facts decisions links
                           pieces questions noticed inbox_entries].freeze
        # Keyed by piece_id, through pieces.
        PIECE_TABLES = %i[piece_links piece_awaits piece_scopes
                          piece_briefs piece_criteria].freeze
        # Keyed by question_id, through questions.
        QUESTION_TABLES = %i[question_choices question_items question_sees
                             question_pictures].freeze
        PICTURE_COLUMNS = %i[id ledger_id name path type event_id].freeze
        TABLES = (LEDGER_TABLES + PIECE_TABLES + QUESTION_TABLES +
                  [:pictures]).freeze

        def self.read(db, ledger_id)
            ledger = db[:ledgers].where(id: ledger_id).first
            raise Unknown, "no ledger L#{ledger_id}" unless ledger
            tables = TABLES.to_h { [it, rows(db, it, ledger_id)] }
            new(ledger, tables)
        end

        def self.rows(db, table, ledger_id)
            set = db[table].order(:id)
            set = set.select(*PICTURE_COLUMNS) if table == :pictures
            set.where(owner(db, table, ledger_id)).all.each(&:freeze).freeze
        end

        # The condition that picks a table's rows of one ledger.
        def self.owner(db, table, ledger_id)
            case table
            when *PIECE_TABLES
                { piece_id: db[:pieces].where(ledger_id:).select(:id) }
            when *QUESTION_TABLES
                { question_id: db[:questions].where(ledger_id:).select(:id) }
            else
                { ledger_id: }
            end
        end

        attr_reader :ledger, :tables

        def initialize(ledger, tables)
            @ledger = ledger.freeze
            @tables = tables.freeze
            freeze
        end

        def ledger_id = ledger[:id]
        def [](table) = tables.fetch(table)
        def ==(other) = other.is_a?(Snapshot) && to_h == other.to_h
        alias eql? ==
        def hash = to_h.hash
        def to_h = { ledger:, tables: }

        TABLES.each { |table| define_method(table) { tables.fetch(table) } }
    end
end
