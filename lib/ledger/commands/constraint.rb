# frozen_string_literal: true

require "ledger/commands/heard"

module Ledger
    module Commands
        # `constraint PATH QUOTE --where W`: a constraint, the user's
        # words and where they were said. A quote not in a message of the
        # user's is warned of unless --said-in says where it was said
        # (Heard).
        class Constraint < CLI::Command
            include Heard

            USAGE = "PATH QUOTE"
            SYNOPSIS = "PATH QUOTE --where W"
            SUMMARY = "a constraint: the user's words verbatim and where " \
                      "they were said"
            WHERE = "--where is empty; say where the user said it"

            private

            def flags(parser)
                parser.on("--where WHERE",
                          "where it was said: a turn, a file") do |value|
                    @opts[:where] = value
                end
                parser.on(*Heard::SAID_IN) { @opts[:said_in] = it }
                dry_run(parser)
            end

            def run(path, quote)
                quote = unquoted(line(quote, "the quote"))
                refuse(WHERE) if @opts[:where].to_s.strip.empty?
                where = line(@opts[:where], "--where")
                text = "\"#{quote}\" — #{where}"
                code = add_item(path, "C", :constraints, quote:, text:,
                                                         said_in:)
                quoted!(quote)
                code
            end

            # The words without their outer double quotes.
            def unquoted(quote)
                unless quote.length >= 2 && quote.match?(/\A".*"\z/)
                    return quote
                end

                line(quote[1..-2], "the quote")
            end
        end
    end
end
