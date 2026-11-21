# frozen_string_literal: true

require "ledger/history"

module Ledger
    module Commands
        # `restore PATH --to E<n> [--dry-run]`: every item-changing event of
        # the ledger after E<n> is reverted, newest first, in one event.
        # Without `--to` the ledger's last ten events are listed and the
        # command is refused.
        class Restore < CLI::Command
            USAGE = "PATH"
            STAMP = "%Y-%m-%d %H:%M:%S"

            private

            def flags(parser)
                parser.on("--to EVENT", "E<n>, the event to go back to") do |to|
                    @opts[:to] = to.strip
                end
                dry_run(parser)
            end

            def run(path)
                return list(path) unless @opts.key?(:to)

                result = write(path) do |change|
                    History.new(journal.db, change).restore(@opts[:to])
                end
                done = "restored: #{Address.parse(path)} is back as at " \
                       "#{@opts[:to]}"
                emit(result, path, lines: result.dry ? [] : [done])
                0
            end

            def list(path)
                events = History.recent(journal.db, journal.ledger(path)[:id])
                events.each { @out.puts line(it) }
                refuse("--to E<n> is required: the events above are the " \
                       "ledger's last #{events.size}")
            end

            def line(event)
                at = Time.at(event[:at] / 1000).strftime(STAMP)
                ["E#{event[:id]}", at, event[:actor], event[:command],
                 event[:summary]].compact.join("  ")
            end
        end
    end
end
