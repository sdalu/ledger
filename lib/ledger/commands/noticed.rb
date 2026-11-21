# frozen_string_literal: true

module Ledger
    module Commands
        # `noticed PATH TEXT`: a line under `Out of scope, noticed`.
        class Noticed < CLI::Command
            USAGE = "PATH TEXT"

            private

            def flags(parser) = dry_run(parser)

            def run(path, text)
                text = line(text, "the text")
                result = write(path, own: text) do |change|
                    change.insert(:noticed, line: "- #{text}")
                end
                emit(result, path, lines: ["- #{text}"])
                0
            end
        end
    end
end
