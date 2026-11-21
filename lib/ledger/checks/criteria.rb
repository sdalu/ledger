# frozen_string_literal: true

module Ledger
    module Checks
        # criteria (at least one; each parses is the schema's) and
        # criteria-pieces.
        module Criteria
            NONE = "need at least one `- [ ] D<n>: ...`"
            # The statuses of a piece that has not finished serving.
            SERVING = (Derive::UNFINISHED + ["blocked"]).freeze

            module_function

            def present(derive) = derive.criteria.empty? ? [NONE] : []

            # Each criterion marked met while a piece serving it is not
            # finished.
            def pieces(derive)
                derive.pieces.flat_map do |piece|
                    next [] unless SERVING.include?(piece[:status])
                    met = derive.serves(piece).select { it[:mark] == "x" }
                    met.map do |criterion|
                        "D#{criterion[:n]} met while #{derive.ref(piece)} " \
                            "[#{piece[:status]}] serves it"
                    end
                end
            end
        end
    end
end
