# frozen_string_literal: true

require "sequel"

require "ledger"
require "ledger/derive"
require "ledger/hooks/places"
require "ledger/render/markdown"

module Ledger
    module Hooks
        # One of the session's ledgers as a hook reads it: its address,
        # its Snapshot, and (unless asked not to) its Derive.
        Found = Data.define(:address, :snapshot, :derive) do
            def status_line = Derive::StatusLine.new(derive).to_s
        end

        # The session's ledgers (the old `ledgers()` locator): the live
        # ledgers whose place is the payload's cwd, cwd/.claude or its
        # scratchpad_dir, in that order. The journal is opened read-only
        # and never created: no file, no ledgers, and the hook passes.
        module Ledgers
            module_function

            def read(payload, derive: true, now: Write.now)
                path = Journal.path
                return [] unless File.file?(path)
                db = Sequel.sqlite(path, readonly: true)
                rows(db, places(payload)).map do |row|
                    found(db, row, derive ? now : nil)
                end
            ensure
                db&.disconnect
            end

            def places(payload) = Places.of(payload)

            def rows(db, places)
                db[:ledgers].where(place: places, closed_at: nil).all
                            .sort_by { [places.index(it[:place]), it[:name]] }
            end

            # NOW nil: the Derive is left out (a hook that needs none of
            # the events).
            def found(db, row, now)
                snapshot = Snapshot.read(db, row[:id])
                address = Address.new(place: row[:place], name: row[:name])
                Found.new(address: address.to_s, snapshot:,
                          derive: now && Derive.read(db, snapshot, now:))
            end
        end
    end
end
