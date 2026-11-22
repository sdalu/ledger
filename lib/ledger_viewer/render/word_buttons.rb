# frozen_string_literal: true

require_relative "terms"

module LedgerViewer
    module Render
        # The buttons a piece offers for its word: the combined one first
        # when it awaits more than one, then one per word. Merge, push and
        # deploy follow a commit, so while the piece still awaits it only
        # the combined button and Commit give them.
        class WordButtons
            LATER = %w[merge push deploy].freeze

            def initialize(scope)
                @scope = scope
            end

            def of(piece)
                id = piece["id"]
                names = piece["awaits"].map { it["word"] }
                lines = piece["scope"].to_h { [it["word"], it["text"]] }
                lead(id, names) + singles(names).map do |word|
                    choice(id, word, single(word), lines[word])
                end
            end

            private

            def lead(id, names)
                names.length > 1 ? [combined(id, names)] : []
            end

            def singles(names)
                return names unless names.include?("commit")

                names - LATER
            end

            def combined(id, names)
                labels = names.map { Terms::WORD_LABEL.fetch(it) }
                inner = @scope.icon("list-checks") + labels.join(" + ")
                choice(id, names.join(", "), inner, nil, "is-combined")
            end

            def single(word)
                @scope.icon(Terms::WORD_ICON.fetch(word)) +
                    Terms::WORD_LABEL.fetch(word)
            end

            def choice(id, value, inner, line, extra = nil)
                said = value.gsub(", ", "-").gsub(" ", "-")
                @scope.partial(
                    "ledger/word_choice",
                    { cls: ["word-choice", extra].compact.join(" "), value:,
                      inner:, line: line || "", wid: "what-#{id}-#{said}" }
                )
            end
        end
    end
end
