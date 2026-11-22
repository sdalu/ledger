# frozen_string_literal: true

require_relative "id_chip"

module LedgerViewer
    module Render
        # What a piece is tied to, as one line under its head: the pieces
        # it waits for, those that wait on it, those it obsoletes, its
        # successor and the question it builds, each part left out when
        # empty and each item an id chip linking to its card or its row.
        class Ties
            def initialize(scope, reading)
                @scope = scope
                @reading = reading
            end

            def piece(piece)
                id = piece["id"]
                parts = [["waits for", chips(piece["after"])],
                         ["needed by", chips(naming(id, "after"))],
                         ["obsoletes", chips(naming(id, "obsoleted_by"))],
                         ["obsoleted by", successor(piece)],
                         ["builds", builds(piece["builds"])]]
                line(parts.reject { it.last.empty? })
            end

            # The chip of a piece's successor, "" when it has none.
            def successor(piece) = chips([piece["obsoleted_by"]].compact)

            private

            # The ids of the pieces whose FIELD (an id or a list of ids)
            # names ID.
            def naming(id, field)
                @reading.pieces.filter_map do |other|
                    other["id"] if Array(other[field]).include?(id)
                end
            end

            def line(parts)
                return "" if parts.empty?

                said = parts.map do |label, html|
                    %(<span class="tie"><span class="tie-label">#{label}) +
                        "</span> #{html}</span>"
                end
                %(<p class="ties">#{said.join}</p>)
            end

            def chips(ids) = ids.map { piece_chip(it) }.join(" ")

            def piece_chip(id)
                item = @reading.pieces.find { it["id"] == id }
                tip = item ? IdChip.summary(item) : ""
                IdChip.link(@scope, id, "#piece-#{id}", tip)
            end

            # The question's card while it is open; once answered, the
            # decision's row in the record, the decision's text on hover.
            def builds(builds)
                return "" unless builds

                id = builds["question"]
                question = @reading.questions.find { it["id"] == id }
                return answered(id, builds) unless question

                IdChip.link(@scope, id, "#q-#{id}", IdChip.summary(question))
            end

            def answered(id, builds)
                at = @reading.decision_ids.index(builds["decision"])
                href = at ? "#dec-#{at}" : "#"
                IdChip.link(@scope, id, href,
                            IdChip.first_line(builds["text"]).to_s)
            end
        end
    end
end
