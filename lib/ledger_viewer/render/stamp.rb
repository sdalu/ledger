# frozen_string_literal: true

require "digest"

module LedgerViewer
    module Render
        # A digest of the live ledgers and of each one's last event:
        # changes when a ledger is opened, closed or written to.
        module Stamp
            # entries: Ledgers::Entry.
            def self.of(entries)
                digest = Digest::SHA1.new
                entries.sort_by(&:id).each do |entry|
                    digest << "#{entry.id}\0#{entry.version}\n"
                end
                digest.hexdigest[0, 16]
            end
        end
    end
end
