# frozen_string_literal: true

require "ledger/stamps"

module Ledger
    # One ledger's rows as plain Ruby values: the ledger row and, per
    # table, its rows as hashes in id order. The shape every reader uses,
    # and the before and after of a write. Pictures come without their
    # bytes, which stay in the journal. Its Stamps, when the events
    # last wrote what a picture shows, ride along outside the rows: two
    # snapshots are equal by their rows alone.
    class Snapshot
        # Keyed by ledger_id.
        LEDGER_TABLES = %i[goals criteria constraints facts decisions links
                           pieces piece_returns piece_assessments
                           questions noticed
                           inbox_entries assumptions].freeze
        # Keyed by piece_id, through pieces.
        PIECE_TABLES = %i[piece_links piece_awaits piece_scopes
                          piece_briefs piece_criteria piece_pictures
                          piece_commits].freeze
        # Keyed by question_id, through questions.
        QUESTION_TABLES = %i[question_choices question_items question_sees
                             question_pictures].freeze
        # Keyed by assumption_id, through assumptions.
        ASSUMPTION_TABLES = %i[assumption_sees assumption_links].freeze
        # The child tables, by the key naming their owner and its table.
        CHILDREN = { piece_id: [:pieces, PIECE_TABLES],
                     question_id: [:questions, QUESTION_TABLES],
                     assumption_id: [:assumptions, ASSUMPTION_TABLES] }.freeze
        PICTURE_COLUMNS = %i[id ledger_id name path type event_id].freeze
        TABLES = (LEDGER_TABLES + PIECE_TABLES + QUESTION_TABLES +
                  ASSUMPTION_TABLES + [:pictures]).freeze

        def self.read(db, ledger_id)
            ledger = db[:ledgers].where(id: ledger_id).first
            raise Unknown, "no ledger L#{ledger_id}" unless ledger
            tables = TABLES.to_h { [it, rows(db, it, ledger_id)] }
            new(ledger, tables, stamps: Stamps.read(db, ledger_id))
        end

        def self.rows(db, table, ledger_id)
            set = db[table].order(:id)
            set = set.select(*PICTURE_COLUMNS) if table == :pictures
            set.where(owner(db, table, ledger_id)).all.each(&:freeze).freeze
        end

        # The condition that picks a table's rows of one ledger.
        def self.owner(db, table, ledger_id)
            key, (parent,) = CHILDREN.find do |_, (_, tables)|
                tables.include?(table)
            end
            return { ledger_id: } unless key

            { key => db[parent].where(ledger_id:).select(:id) }
        end

        attr_reader :ledger, :tables, :stamps

        def initialize(ledger, tables, stamps: Stamps::NONE)
            @ledger = ledger.freeze
            @tables = tables.freeze
            @stamps = stamps
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
