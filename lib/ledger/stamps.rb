# frozen_string_literal: true

module Ledger
    # What the events say a picture showed: when each picture row was
    # last placed on its item (ms), and the fields a picture shows as
    # they stood at a given time, so the pictures-fresh check compares
    # them with the rows as they are. Read from event_rows, every write's
    # after.
    #
    #     stamps = Ledger::Stamps.read(db, ledger_id)
    #     stamps.placed(:piece_pictures, 9)  # => ms
    #     stamps.fields_at(:pieces, 4, ms)   # => {"plan" => "…", …}
    #     stamps.choices_at(2, ms)           # => [[label, effect, cost]]
    class Stamps
        # The fields of each table a picture shows.
        FIELDS = { pieces: %w[plan detail problem],
                   questions: %w[detail problem] }.freeze
        CHOICE = %w[label effect cost].freeze
        PLACES = %w[piece_pictures question_pictures].freeze

        def self.read(db, ledger_id)
            rows = db[:event_rows].join(:events, id: :event_id)
                                  .where(Sequel[:events][:ledger_id] =>
                                             ledger_id)
                                  .order(Sequel[:events][:id],
                                         Sequel[:event_rows][:rowid])
            history = FIELDS.to_h do |table, names|
                [table, history(rows, table, names)]
            end
            new(history:, choices: choices(rows), places: places(rows))
        end

        # {row id => [[ms, {field => value}]]} of TABLE's rows, in event
        # order, a deletion left out.
        def self.history(rows, table, names)
            rows.where(tbl: table.to_s).exclude(after: nil)
                .select(:row_id, :at, *names.map { extract(it) }).all
                .group_by { it[:row_id] }.transform_values do |writes|
                    writes.map { [it[:at], it.slice(*names.map(&:to_sym))] }
                end
        end

        # [[ms, row id, question id, [label, effect, cost] or nil]] of
        # every choice written, in event order; nil for a deletion.
        def self.choices(rows)
            owner = Sequel.lit("json_extract(coalesce(after, before), " \
                               "'$.question_id')").as(:question_id)
            rows.where(tbl: "question_choices")
                .select(:row_id, :at, Sequel.lit("after IS NULL").as(:gone),
                        owner, *CHOICE.map { extract(it) }).all
                .map do |row|
                    values = row.values_at(*CHOICE.map(&:to_sym))
                    [row[:at], row[:row_id], row[:question_id],
                     (values unless row[:gone] == 1)]
                end
        end

        def self.extract(field)
            Sequel.lit("json_extract(after, '$.#{field}')").as(field.to_sym)
        end

        # {[table, row id] => ms} of the picture rows' last write.
        def self.places(rows)
            rows.where(tbl: PLACES).exclude(after: nil)
                .group(:tbl, :row_id)
                .select(:tbl, :row_id, Sequel.function(:max, :at).as(:at))
                .all.to_h { [[it[:tbl].to_sym, it[:row_id]], it[:at]] }
        end

        def initialize(history: {}, choices: [], places: {})
            @history = history
            @choices = choices
            @places = places
            freeze
        end

        NONE = new

        # When the picture row ID of TABLE was last placed; nil unknown.
        def placed(table, id) = @places[[table, id]]

        # {field => value} of an item's row as it stood at AT; {} when no
        # write is known by then.
        def fields_at(table, id, at)
            writes = @history.fetch(table, {}).fetch(id, [])
            last = writes.select { |time, _| time <= at }.last
            last ? last.last.transform_keys(&:to_s) : {}
        end

        # The question's choices as they stood at AT, sorted.
        def choices_at(question_id, at)
            alive = {}
            @choices.each do |time, row_id, owner, values|
                next unless owner == question_id && time <= at

                alive[row_id] = values
            end
            alive.values.compact.sort_by { it.map(&:to_s) }
        end
    end
end
