# frozen_string_literal: true

require "ledger/inbox"

module Ledger
    module Commands
        # `inbox PATH [--wait [--timeout S] | --follow [--quiet S]]`: the
        # entries no session has taken, or a wait for them. `--wait` ends
        # with 1 at its timeout; `--follow` runs until it is stopped.
        class Inbox < CLI::Command
            USAGE = "PATH"
            QUIET = 60.0
            STOPS = %w[TERM INT HUP].freeze

            private

            def flags(parser)
                parser.on("--wait", "block until an entry is pending") do
                    @opts[:wait] = true
                end
                parser.on("--follow", "print each entry once, until stopped") do
                    @opts[:follow] = true
                end
                seconds(parser)
            end

            def seconds(parser)
                parser.on("--timeout S", Float, "stop after S seconds") do |s|
                    @opts[:timeout] = s
                end
                parser.on("--quiet S", Float, "the lull that releases a " \
                                              "followed burst") do |s|
                    @opts[:quiet] = s
                end
            end

            def run(path)
                ledger = journal.ledger(path)
                return watch(ledger[:id]) if @opts[:wait] || @opts[:follow]

                rows = Ledger::Inbox.pending(snapshot(path))
                @out.puts rows.empty? ? "inbox: nothing pending" : shown(rows)
                0
            end

            def shown(rows) = rows.map { Ledger::Inbox.show(it) }.join("\n")

            def watch(ledger_id)
                options = { follow: @opts[:follow], timeout: @opts[:timeout],
                            quiet: @opts.fetch(:quiet, QUIET) }
                watch = Ledger::Inbox::Watch.new(journal, ledger_id, @out,
                                                 **options)
                @opts[:follow] ? stoppable { watch.call } : watch.call
            end

            # A stop signal ends the follow with 0, after the held burst is
            # printed.
            def stoppable
                before = STOPS.to_h { [it, Signal.trap(it) { exit(0) }] }
                yield
            ensure
                before&.each { |sig, old| Signal.trap(sig, old || "DEFAULT") }
            end
        end
    end
end
