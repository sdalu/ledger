# frozen_string_literal: true

require "ledger/history"

module Ledger
    module Commands
        # `undo PATH [--dry-run]`: the ledger's last event that changed its
        # items is reverted, in an event of its own (one level). The event
        # that made the ledger (`new`) is not one: there is nothing to undo
        # before it.
        class Undo < CLI::Command
            USAGE = "PATH"
            SUMMARY = "revert the ledger's last event"

            private

            def flags(parser) = dry_run(parser)

            def run(path)
                result = write(path) do |change|
                    refuse("nothing to undo") if made_by_new?(change)
                    History.new(journal.db, change).undo
                end
                done = "undone: #{Address.parse(path)} is back as it was " \
                       "before E#{result.value}"
                emit(result, path, lines: result.dry ? [] : [done])
                0
            end

            # Whether the event undo would revert is the one that made the
            # ledger.
            def made_by_new?(change)
                journal.db[:events].where(ledger_id: change.ledger_id)
                       .where(Sequel[:id] < change.event_id)
                       .exclude(command: History::SILENT)
                       .reverse(:id).get(:command) == "new"
            end
        end
    end
end
