# frozen_string_literal: true

require "ledger/commands/answer"

module Ledger
    module Commands
        # `take PATH ID...`: the viewer's entries a session has filed are
        # marked taken, in one `take` event; an entry taken before is
        # refused, its words were filed there.
        class Take < CLI::Command
            include Taking

            USAGE = "PATH ID..."
            SYNOPSIS = "PATH N<n>..."
            SUMMARY = "mark the viewer's entries filed, in one event"

            private

            def arguments(args)
                return args if args.size >= 2

                refuse("usage: ledger take #{USAGE}")
            end

            def run(path, *ids)
                ids = ids.uniq
                result = write(path) do |change|
                    take(change, ids)
                    change.summary = "taken: #{ids.join(", ")}"
                end
                @out.puts take_line(result.after, ids)
                0
            end
        end
    end
end
