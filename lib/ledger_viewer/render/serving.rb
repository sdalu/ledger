# frozen_string_literal: true

require_relative "links"
require_relative "status"

module LedgerViewer
    module Render
        # The backlinks of a criterion: the questions citing it as meta
        # text, and the pieces serving it counted, their links folded.
        # A question cites a criterion with `see`.
        class Serving
            def initialize(scope, reading)
                @scope = scope
                @reading = reading
            end

            # [the meta text, the fold of the pieces], each "" when empty.
            def of(criterion)
                id = criterion["id"]
                mine = @reading.pieces.select { it["for"].include?(id) }
                cited = citing(id).map { "[#{it}](#q-#{it})" }
                [(cited.empty? ? "" : "cited by #{cited.join(", ")}"),
                 fold(mine)]
            end

            private

            # The ids of the questions that cite `id`.
            def citing(id)
                @reading.questions.select { it["see"].include?(id) }
                        .map { it["id"] }
            end

            def fold(mine)
                return "" if mine.empty?

                links = mine.map do |piece|
                    "[#{piece["id"]}](#piece-#{piece["id"]}) " \
                        "#{Status.of(piece)}"
                end.join(", ")
                counts = Links.counts(mine.map { it["status"] })
                "<details class=\"piece-list\"><summary>evidence from " \
                    "#{counts}</summary><div class=\"meta\">" \
                    "#{@scope.inline(links)}</div></details>"
            end
        end
    end
end
