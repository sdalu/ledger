# frozen_string_literal: true

module Ledger
    module Commands
        # `noticed PATH TEXT`: a line under `Out of scope, noticed`; its
        # id, Z<n>, is the first line printed.
        class Noticed < CLI::Command
            USAGE = "PATH TEXT"
            SUMMARY = "a line under Out of scope, noticed"

            private

            def flags(parser) = dry_run(parser)

            def run(path, text)
                text = line(text, "the text")
                result = write(path, own: text) do |change|
                    "Z#{change.insert(:noticed, line: "- #{text}")}"
                end
                emit(result, path, first: result.value, lines: ["- #{text}"])
                0
            end
        end
    end
end
