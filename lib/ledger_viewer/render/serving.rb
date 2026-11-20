# frozen_string_literal: true

require_relative "links"
require_relative "terms"

module LedgerViewer
    module Render
        # The backlinks of a criterion: the questions citing it as meta
        # text, and the pieces serving it counted, their links folded.
        # serving() of ledger-serve.py.
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

            # The ids of the questions that cite `id` (a question without
            # one is spelled the way Python spells None).
            def citing(id)
                found = @reading.questions.select do |question|
                    see = Terms.split_fields(question["text"])[1]
                               .fetch("see", "")
                    (Terms.link_ids("see", see) || []).include?(id)
                end
                found.map { it["id"] || "None" }
            end

            def fold(mine)
                return "" if mine.empty?

                links = mine.map do |piece|
                    "[#{piece["id"]}](#piece-#{piece["id"]}) #{piece["status"]}"
                end.join(", ")
                counts = Links.counts(mine.map { it["status"] })
                "<details class=\"piece-list\"><summary>evidence from " \
                    "#{counts}</summary><div class=\"meta\">" \
                    "#{@scope.inline(links)}</div></details>"
            end
        end
    end
end
