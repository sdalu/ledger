# frozen_string_literal: true

require "digest"

require "ledger"
require "ledger/read"
require "ledger/waker"

require_relative "render/age"

module LedgerViewer
    # The live ledgers of the journal, read afresh each time, and what a
    # page reads of one: its JSON v1 document (Ledger::Read). A closed
    # ledger keeps its live one's address, so it has no id of its own in
    # a URL and is not listed.
    class Ledgers
        # id: what names a ledger in a URL, the first ten hex digits of
        # sha1(address); path: its address; ledger_id: its row; version:
        # its last event, which moves whenever the ledger does.
        Entry = Data.define(:id, :path, :project, :ledger_id, :version)

        attr_reader :journal

        def initialize(journal) = @journal = journal

        # Every live ledger, in the journal's order.
        def all
            db = @journal.db
            last = db[:events].where(ledger_id: Sequel[:ledgers][:id])
                              .select { max(:id) }
            db[:ledgers].where(closed_at: nil).order(:id)
                        .select_append(last.as(:version)).all
                        .map { entry(it) }
        end

        def find(lid) = all.find { it.id == lid }

        # The ledger's JSON v1 document, string keys. The private-use
        # characters that bracket an age are dropped from its texts here:
        # only the viewer's own Age.of may bracket one, and a journal's
        # text holding them would otherwise forge an element.
        def read(entry)
            document = Ledger::Read.ledger(@journal, entry.ledger_id)
            Ledger::Read.parse(Render::Age.strip(JSON.generate(document)))
        end

        # The bytes and type of a picture's file, or nil: NAME is a
        # picture of the ledger, PATH its file under it ("" for one file).
        def picture(entry, name, path)
            @journal.db[:pictures]
                    .where(ledger_id: entry.ledger_id, name:, path:)
                    .select(:type, :bytes).first
        end

        # The picture REST names, NAME or NAME/PATH, or nil: a name may
        # hold a slash, so the longest name leading REST is the one.
        def picture_at(entry, rest)
            name = picture_names(entry)
                   .select { rest == it || rest.start_with?("#{it}/") }
                   .max_by(&:length) or return
            picture(entry, name, rest[(name.length + 1)..].to_s)
        end

        # The names of a ledger's pictures.
        def picture_names(entry)
            @journal.db[:pictures].where(ledger_id: entry.ledger_id)
                    .distinct.select_map(:name)
        end

        # The waker of a ledger: whether it is on, and its wakes, newest
        # first.
        Waking = Data.define(:on, :wakes)

        def waker(entry)
            db = @journal.db
            on = db[:ledgers].where(id: entry.ledger_id).get(:waker)
            Waking.new(on:, wakes: Ledger::Waker.wakes(db, entry.ledger_id))
        end

        # The waker of a ledger switched ON (true) or off, in one event
        # of ACTOR.
        def switch_waker(entry, on, actor:)
            Ledger::Waker.switch(@journal, entry.path, on, actor:)
        end

        def self.url_id(address) = Digest::SHA1.hexdigest(address)[0, 10]

        private

        def entry(row)
            address = Ledger::Address.new(place: row[:place],
                                          name: row[:name]).to_s
            Entry.new(id: self.class.url_id(address), path: address,
                      project: row[:project], ledger_id: row[:id],
                      version: row[:version] || 0)
        end
    end
end
