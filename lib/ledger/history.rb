# frozen_string_literal: true

require "json"

module Ledger
    # The ledger's history (docs/journal.md, section 2): `undo` reverts
    # the last event that changed its items, `restore` every such event
    # after one. Inside a write: the revert is itself the writing event,
    # its row changes go through the change handle.
    #
    #     Ledger::Write.run(journal, address, "undo", []) do |change|
    #         Ledger::History.new(journal.db, change).undo
    #     end
    #
    # A row is written back to its before only while it still equals the
    # after the event gave it. Inbox entries are never reverted (the
    # user's channel, takes included) and a picture's bytes were never
    # in the history, so an undone mockup leaves its blobs.
    class History
        # The events that change no item of the ledger.
        SILENT = %w[take inbox close].freeze
        EVENT = /\AE([1-9]\d*)\z/
        KEPT = %w[inbox_entries].freeze

        # The ledger's newest LIMIT events, newest first.
        def self.recent(db, ledger_id, limit = 10)
            db[:events].where(ledger_id:).reverse(:id).limit(limit).all
        end

        def initialize(db, change)
            @db = db
            @change = change
        end

        # Reverts the ledger's last item-changing event, unless that is
        # an undo: one level. -> the event's id.
        def undo
            event = events.first
            raise Refused, "nothing to undo" if event.nil? ||
                                                event[:command] == "undo"

            revert(event, "undo")
            finish(event[:id], "undid E#{event[:id]}")
        end

        # Reverts every item-changing event after the one REF names, newest
        # first. -> that event's id.
        def restore(ref)
            from = target(ref)
            later = events.where(Sequel[:id] > from).all
            raise Refused, "nothing to restore after E#{from}" if later.empty?

            later.each { revert(it, "restore") }
            finish(from, "restored to E#{from}")
        end

        private

        # The ledger's item-changing events before this write, newest
        # first.
        def events
            @db[:events].where(ledger_id: @change.ledger_id)
                        .where(Sequel[:id] < @change.event_id)
                        .exclude(command: SILENT).reverse(:id)
        end

        def target(ref)
            id = EVENT.match(ref.to_s)&.then { it[1].to_i } or
                raise Refused, "--to takes an event id like E12"
            return id if @db[:events].where(id:, ledger_id: @change.ledger_id)
                                     .any?

            raise Refused, "E#{id} is not this ledger's"
        end

        def finish(id, summary)
            @db[:events].where(id: @change.event_id).update(undoes: id)
            @change.summary = summary
            id
        end

        def revert(event, verb)
            lines = @db[:event_rows].where(event_id: event[:id])
                                    .exclude(tbl: KEPT)
                                    .reverse(:rowid).all
            lines.each { write_back(event, it, verb) }
        end

        def write_back(event, line, verb)
            table = line[:tbl].to_sym
            current = @db[table].where(id: line[:row_id]).first
            unless same?(current, line[:after])
                raise Refused, "#{table} row #{line[:row_id]} changed since " \
                               "E#{event[:id]}: nothing to #{verb} safely"
            end
            before = line[:before]&.then do |json|
                JSON.parse(json, symbolize_names: true)
            end
            apply(table, line[:row_id], current, before)
        end

        # Whether the row as it is now is the row an event left (JSON).
        def same?(current, after)
            return current.nil? if after.nil?

            current && JSON.parse(current.to_json) == JSON.parse(after)
        end

        def apply(table, id, current, before)
            if before.nil?
                @change.delete(table, id)
            elsif current.nil?
                reinsert(table, id, before)
            else
                @change.update(table, id, **before.except(:id))
            end
        end

        # The row comes back under its own id; a row the write path stamps
        # with the event is given its first event back.
        def reinsert(table, id, before)
            @change.insert(table, **before)
            event_id = before[:event_id]
            return unless event_id && event_id != @change.event_id

            @change.update(table, id, event_id:)
        end
    end
end
