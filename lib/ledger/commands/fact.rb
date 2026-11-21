# frozen_string_literal: true

module Ledger
    module Commands
        # `fact PATH TEXT`: a fact and where it was found, split at the
        # first ` — `.
        class Fact < CLI::Command
            USAGE = "PATH TEXT"
            SYNOPSIS = "PATH 'TEXT \u2014 POINTER'"
            SUMMARY = "a fact and where it was found, split at the first ' " \
                      "\u2014 '"
            SHAPE = /\A(?<text>.+?) — (?<pointer>\S.*)\z/

            private

            def flags(parser) = dry_run(parser)

            def run(path, text)
                match = SHAPE.match(text.strip) or
                    refuse("a fact ends with — and where it was found")
                add_item(path, "F", :facts, text: match[:text],
                                            pointer: match[:pointer])
            end
        end
    end
end
