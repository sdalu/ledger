# frozen_string_literal: true

require "digest"

module LedgerViewer
    module Render
        # A digest of the live ledgers and of each one's last event:
        # changes when a ledger is opened, closed or written to. A
        # ledger's own page has the stamp of that ledger alone.
        module Stamp
            # entries: Ledgers::Entry.
            def self.of(entries)
                digest = Digest::SHA1.new
                entries.sort_by(&:id).each do |entry|
                    digest << "#{entry.id}\0#{entry.version}\n"
                end
                digest.hexdigest[0, 16]
            end

            # The stamp of the one ledger `lid` among `entries`, which a
            # page of that ledger watches; a ledger closed or unknown has
            # one that no live ledger has, so its page learns it changed.
            def self.ledger(entries, lid)
                entry = entries.find { it.id == lid }
                return of([entry]) if entry

                Digest::SHA1.hexdigest("#{lid}\0gone\n")[0, 16]
            end
        end
    end
end
