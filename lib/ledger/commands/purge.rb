# frozen_string_literal: true

require "ledger/backup"
require "ledger/purge"

module Ledger
    module Commands
        # `purge L<n> --confirmed`: a closed ledger made by mistake is
        # removed from the journal, its events and every row of its items
        # with it. The journal is first copied (Backup), the copy named
        # on the last line; the delete is one transaction. Without
        # --confirmed it prints what would go and writes nothing.
        class Purge < CLI::Command
            USAGE = "L<n>"
            SYNOPSIS = "L<n> --confirmed"
            LEDGER = /\AL([1-9]\d*)\z/
            SUMMARY = "remove a closed ledger and its events from the " \
                      "journal, after a backup copy; irreversible: not an " \
                      "event, so undo and restore cannot bring it back, " \
                      "only the backup. L<n> is the id `close` prints; " \
                      "without --confirmed, print what would go, exit 2"

            private

            def flags(parser)
                parser.on("--confirmed", "do it, after the backup") do
                    @opts[:confirmed] = true
                end
            end

            def run(name)
                row = closed(name)
                purge = Ledger::Purge.new(journal.db, row[:id])
                return confirmed(row, purge) if @opts[:confirmed]

                describe(row, purge.counts)
                refuse("nothing removed; --confirmed removes it")
            end

            # The closed ledger L<n> names; refused when it does not exist
            # or is live.
            def closed(name)
                match = LEDGER.match(name) or
                    refuse("#{name} is not a ledger id (L<n>)")
                row = journal.ledger_by_id(match[1].to_i)
                return row if row[:closed_at]

                refuse("L#{row[:id]} is live; only a closed ledger is purged")
            end

            def describe(row, counts)
                @out.puts "would remove #{title(row)}"
                lines(counts).each { @out.puts it }
            end

            # "L3: PLACE NAME, closed TIME", the name left out when empty.
            def title(row)
                at = Time.at(row[:closed_at] / 1000).strftime("%F %T")
                name = row[:name].empty? ? "" : " #{row[:name]}"
                "L#{row[:id]}: #{row[:place]}#{name}, closed #{at}"
            end

            def lines(counts)
                counts.reject { |_, n| n.zero? }
                      .map { |table, n| "  #{table}: #{n}" }
            end

            def confirmed(row, purge)
                path = backup(row)
                removed = journal.transaction { purge.delete }
                @out.puts "purged #{title(row)}"
                lines(removed).each { @out.puts it }
                @out.puts "backup: #{path}"
                0
            end

            # The journal copied beside itself; refused when the name is
            # taken, before anything is removed.
            def backup(row)
                path = Backup.purge_path(journal.path, row[:id])
                Backup.copy(journal.db, path)
                path
            rescue Backup::Exists => e
                refuse("#{e.message}; nothing removed")
            end
        end
    end
end
