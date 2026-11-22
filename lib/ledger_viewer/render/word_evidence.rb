# frozen_string_literal: true

require_relative "reading"

module LedgerViewer
    module Render
        # What a word rests on, read where the word is given: the piece's
        # evidence, just above its buttons, and a link to its row in the
        # record, which only a piece out of flight has.
        module WordEvidence
            module_function

            # The line, or "" when the piece names no evidence.
            def html(scope, piece)
                said = piece["evidence"].to_s
                return "" if said.strip.empty?

                %(<p class="word-evidence"><strong>Evidence:</strong> ) \
                    "#{scope.inline(said)}#{record_link(piece)}</p>"
            end

            def record_link(piece)
                return "" if Reading::IN_FLIGHT.include?(piece["status"])

                %( · <a href="#piece-#{piece["id"]}">its row in the record</a>)
            end
        end
    end
end
