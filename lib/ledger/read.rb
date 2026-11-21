# frozen_string_literal: true

require "json"

require "ledger/derive"
require "ledger/render/json"

module Ledger
    # What the viewer and the hooks read (docs/journal.md, section 6):
    # one ledger of the journal as its JSON v1 document, derived values
    # taken from Derive at the time NOW.
    #
    #     doc = Ledger::Read.ledger(journal, "/work/alpha/LEDGER.md")
    #     doc = Ledger::Read.ledger(journal, 3)       # by id, live or closed
    #     Ledger::Read.parse(text)                    # a document's text
    module Read
        SCHEMA = Render::Json::SCHEMA

        module_function

        # REF is an address (a live ledger) or an Integer (a ledger id).
        def ledger(journal, ref, now: Write.now)
            row = ref.is_a?(Integer) ? by_id(journal, ref) : journal.ledger(ref)
            document(journal.db, row[:id], now:)
        end

        # The index document: every ledger of the journal, live and closed.
        def index(journal, now: Write.now)
            db = journal.db
            parts = db[:ledgers].select_map(:id).map do |id|
                snapshot = Snapshot.read(db, id)
                Render::Json::Part.new(
                    snapshot:, derive: Derive.read(db, snapshot, now:),
                    updated_at: updated_at(db, snapshot)
                )
            end
            Render::Json.index(parts)
        end

        def by_id(journal, id) = journal.ledger_by_id(id)

        def document(db, ledger_id, now: Write.now)
            snapshot = Snapshot.read(db, ledger_id)
            derive = Derive.read(db, snapshot, now:)
            Render::Json.ledger(snapshot, derive, context(db, snapshot))
        end

        # A document's text as a Hash; Refused when its schema is not
        # the one this reader knows.
        def parse(text) = accept(JSON.parse(text))

        def accept(document)
            schema = document.is_a?(Hash) ? document["schema"] : nil
            return document if schema == SCHEMA

            raise Refused, "JSON schema #{schema.inspect}: this reader " \
                           "knows #{SCHEMA}"
        end

        def context(db, snapshot)
            Render::Json::Context.new(
                updated_at: updated_at(db, snapshot),
                sizes: sizes(db, snapshot.ledger_id),
                events: events(db, snapshot),
                claims: claims(db, snapshot.ledger_id)
            )
        end

        # {picture id => bytes}: the lengths, never the blobs.
        def sizes(db, ledger_id)
            size = Sequel.function(:length, :bytes).as(:size)
            db[:pictures].where(ledger_id:).select(:id, size).all
                         .to_h { [it[:id], it[:size]] }
        end

        # The last event's time.
        def updated_at(db, snapshot)
            db[:events].where(ledger_id: snapshot.ledger_id).max(:at)
        end

        # {id => {at:, actor:}} of the events the rows name: the briefs
        # and the takes.
        def events(db, snapshot)
            ids = [*snapshot.piece_briefs.map { it[:event_id] },
                   *snapshot.inbox_entries.filter_map { it[:taken_id] }]
            db[:events].where(id: ids).select(:id, :at, :actor).all
                       .to_h { [it[:id], it.slice(:at, :actor)] }
        end

        # {piece id => ms}: the event that gave the piece to the session
        # holding it now.
        def claims(db, ledger_id)
            rows = db[:event_rows].join(:events, id: :event_id)
                                  .where(ledger_id:, tbl: "pieces")
                                  .order(Sequel[:events][:id])
                                  .select_map(%i[at row_id before after])
            rows.each_with_object({}) do |(at, row_id, before, after), out|
                held = claimed_by(after)
                out[row_id] = at if held && held != claimed_by(before)
                out.delete(row_id) unless held
            end
        end

        def claimed_by(json) = json && JSON.parse(json)["claimed_by"]
    end
end
