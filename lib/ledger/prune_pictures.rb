# frozen_string_literal: true

require "json"

module Ledger
    # The pictures nothing names any more, and the stored contents no
    # picture points to. A picture is in use while a piece_pictures row
    # (a piece's before or after), a question_pictures row or a
    # question_choices.picture of its ledger names it; every reader draws
    # its pictures through those names. A row no name reaches is only
    # kept so that undo or restore can name it again.
    class PrunePictures
        DAY_MS = 86_400_000
        PICTURES = Sequel[:pictures]

        # One name of a ledger nothing names: its FILES, their BYTES, the
        # time it was PLACED (ms) and the OWNER (P<n> or O<n>) that last
        # named it, nil when no event says.
        Unused = Data.define(:ledger_id, :name, :files, :bytes, :placed,
                             :owner)

        # What a prune removes: pictures rows, contents rows, and the
        # bytes the contents held.
        Counts = Data.define(:pictures, :blobs, :bytes)

        # DB's pictures older than OLDER days at NOW (a Time), of ledger
        # LEDGER_ID or of every ledger.
        def initialize(db, ledger_id: nil, older: 7, now: Time.now)
            @db = db
            @ledger_id = ledger_id
            @cutoff = (now.to_f * 1000).to_i - (older * DAY_MS)
        end

        # The Unused names, by ledger then name.
        def unused
            owners = Hash.new { |hash, id| hash[id] = Owners.new(@db, id) }
            candidates.map do |(ledger, name), rows|
                Unused.new(ledger_id: ledger, name:, files: rows.size,
                           bytes: rows.sum { it[:size] }, placed: placed(rows),
                           owner: owners[ledger].of(name))
            end
        end

        # The Counts of removing `unused`.
        def counts
            ids = picture_ids(unused)
            gone = orphans(ids)
            Counts.new(pictures: ids.size, blobs: gone.count,
                       bytes: gone.sum(:size).to_i)
        end

        # Deletes the unused pictures and every content no remaining
        # picture points to, inside the caller's transaction; -> Counts.
        def delete
            ids = picture_ids(unused)
            gone = orphans(ids)
            counts = Counts.new(pictures: ids.size, blobs: gone.count,
                                bytes: gone.sum(:size).to_i)
            shas = gone.select_map(:sha256)
            @db[:pictures].where(id: ids).delete
            @db[:picture_blobs].where(sha256: shas).delete
            counts
        end

        private

        # The picture rows, by name, of the names nothing names and
        # whose event is older than the cutoff.
        def candidates
            picture_rows.group_by { [it[:ledger_id], it[:name]] }
                        .reject do |(ledger, name), rows|
                named(ledger).include?(name) || placed(rows) >= @cutoff
            end
        end

        # A name's time: its newest file's event.
        def placed(rows) = rows.map { it[:at] }.max

        # Every picture row in scope, with its size and the time of the
        # event that placed it, by ledger then name.
        def picture_rows
            set = joined.order(PICTURES[:ledger_id], PICTURES[:name])
            set = set.where(PICTURES[:ledger_id] => @ledger_id) if @ledger_id
            set.all
        end

        def joined
            @db[:pictures].join(:picture_blobs, sha256: :sha256)
                          .join(:events, id: PICTURES[:event_id])
                          .select_all(:pictures)
                          .select_append(Sequel[:picture_blobs][:size],
                                         Sequel[:events][:at])
        end

        def picture_ids(unused)
            keys = unused.to_h { [[it.ledger_id, it.name], true] }
            picture_rows.select { keys[[it[:ledger_id], it[:name]]] }
                        .map { it[:id] }
        end

        # The contents that no picture outside IDS points to.
        def orphans(ids)
            kept = @db[:pictures].exclude(id: ids).select(:sha256)
            @db[:picture_blobs].exclude(sha256: kept)
        end

        # The names of LEDGER a piece or a question names.
        def named(ledger)
            @named ||= {}
            @named[ledger] ||= names(ledger)
        end

        def names(ledger)
            [*piece_names(ledger), *question_names(ledger)].compact
        end

        def piece_names(ledger)
            pieces = @db[:pieces].where(ledger_id: ledger).select(:id)
            @db[:piece_pictures].where(piece_id: pieces).select_map(:name)
        end

        # The names the questions' pictures and choices carry.
        def question_names(ledger)
            ids = @db[:questions].where(ledger_id: ledger).select(:id)
            @db[:question_pictures].where(question_id: ids).select_map(:name) +
                @db[:question_choices].where(question_id: ids)
                                      .select_map(:picture)
        end

        # The owner a name last had, from the rows the ledger's events
        # changed in the tables that name pictures.
        class Owners
            TABLES = { "piece_pictures" => [:piece_id, :pieces, "P", :name],
                       "question_pictures" => [:question_id, :questions, "O",
                                               :name],
                       "question_choices" => [:question_id, :questions, "O",
                                              :picture] }.freeze

            def initialize(db, ledger)
                @db = db
                @ledger = ledger
            end

            # P<n> or O<n>, nil when no event names NAME.
            def of(name) = last[name]

            private

            def last
                @last ||= changed.each_with_object({}) do |row, out|
                    key, table, kind, field = TABLES.fetch(row[:tbl])
                    ref = ref(row, key, table, kind) or next
                    names(row, field).each { out[it] = ref }
                end
            end

            # Event rows of the tables, oldest first.
            def changed
                @db[:event_rows].join(:events, id: :event_id)
                                .where(ledger_id: @ledger, tbl: TABLES.keys)
                                .order(Sequel[:events][:id])
                                .select(:tbl, :before, :after).all
            end

            def names(row, field)
                %i[before after].filter_map do |side|
                    JSON.parse(row[side])[field.to_s] if row[side]
                end
            end

            def ref(row, key, table, kind)
                json = JSON.parse(row[:after] || row[:before])
                n = @db[table].where(id: json[key.to_s]).get(:n)
                "#{kind}#{n}" if n
            end
        end
    end
end
