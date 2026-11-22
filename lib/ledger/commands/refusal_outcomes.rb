# frozen_string_literal: true

require "ledger/outcomes"

module Ledger
    module Commands
        # A writer word's refusal as outcomes rows (Outcomes): one per
        # rule a Worse names ("FAIL rule -- detail"), else one under the
        # refusal's own rule (Refused#rule), `usage` for an option the
        # parser refused, `constraint` for a row the schema refused, none
        # for a preview (Refused#recorded?); `final` per FAIL line of a
        # close the finish gate refused. The
        # ledger is the live one at the first word naming an address, the
        # ref the first word naming a piece or question.
        class RefusalOutcomes
            REF = /\A[PO][1-9]\d*\z/
            FAIL = /\AFAIL (?<rule>\S+)(?: -- (?<detail>.*))?\z/

            def initialize(words, err:)
                @words = words
                @err = err
            end

            def record(error) = Outcomes.write(rows(error), err: @err)

            # A close the finish gate refused: one row `final` per FAIL
            # line LINES give, the line its detail.
            def final(lines)
                Outcomes.write(lines.map { row("final", it) }, err: @err)
            end

            def rows(error)
                return [] if error.is_a?(Refused) && !error.recorded?
                return worse(error) if error.is_a?(Worse)

                [row(rule(error), error.message)]
            end

            private

            def worse(error)
                error.message.lines(chomp: true).map do |line|
                    found = FAIL.match(line)
                    next row("worse", line) unless found

                    row(found[:rule], found[:detail])
                end
            end

            def rule(error)
                case error
                when Refused then error.rule
                when OptionParser::ParseError then "usage"
                else "constraint"
                end
            end

            def row(rule, detail)
                { kind: "refusal", rule:, address:, ref:, detail: }
            end

            def address
                word = @words.find { ADDRESS_FILE.match?(File.basename(it)) }
                word && Address.parse(word)
            end

            def ref = @words.find { REF.match?(it.to_s) }
        end
    end
end
