# frozen_string_literal: true

require_relative "id_chip"

module LedgerViewer
    module Render
        # What a piece is tied to, as one line under its head: the pieces
        # it waits for (each with its state, the line opening with
        # 'ready —' on a planned piece whose waits are all settled), those
        # that wait on it, those it obsoletes, its successor and the
        # question it builds, each part left out when empty and each item
        # an id chip linking to where the page draws it.
        class Ties
            def initialize(scope, reading)
                @scope = scope
                @reading = reading
            end

            def piece(piece)
                id = piece["id"]
                parts = [["waits for", waits(piece["after"])],
                         ["needed by", chips(naming(id, "after"))],
                         ["obsoletes", chips(naming(id, "obsoleted_by"))],
                         ["obsoleted by", successor(piece)],
                         ["builds", builds(piece["builds"])]]
                line(parts.reject { it.last.empty? }, ready?(piece))
            end

            # The chip of a piece's successor, "" when it has none.
            def successor(piece) = chips([piece["obsoleted_by"]].compact)

            private

            # A planned piece all of whose waits are settled.
            def ready?(piece)
                after = piece["after"]
                piece["status"] == "planned" && after.any? &&
                    after.all? { settled?(it) }
            end

            def settled?(id) = find(id)&.fetch("settled", false)

            def find(id) = @reading.pieces.find { it["id"] == id }

            # The ids of the pieces whose FIELD (an id or a list of ids)
            # names ID.
            def naming(id, field)
                @reading.pieces.filter_map do |other|
                    other["id"] if Array(other[field]).include?(id)
                end
            end

            def line(parts, ready)
                return "" if parts.empty?

                lead = ready ? %(<span class="tie-ready">ready —</span>) : ""
                said = parts.map do |label, html|
                    %(<span class="tie"><span class="tie-label">#{label}) +
                        "</span> #{html}</span>"
                end
                %(<p class="ties">#{lead}#{said.join}</p>)
            end

            def chips(ids) = ids.map { piece_chip(it) }.join(" ")

            def piece_chip(id)
                item = find(id)
                tip = item ? IdChip.summary(item) : ""
                IdChip.link(@scope, id, href(item || { "id" => id }), tip)
            end

            # A waited-for piece: settled ones muted with a tick and
            # 'settled' on hover, the others plain with their status.
            def waits(ids)
                ids.map do |id|
                    item = find(id)
                    next piece_chip(id) unless item

                    state = item["settled"] ? "settled" : item["status"]
                    tip = [IdChip.summary(item), state].join(" · ")
                    IdChip.link(@scope, id, href(item), tip,
                                done: item["settled"])
                end.join(" ")
            end

            # Where the page draws PIECE: on its question's card while it
            # builds an open question, on its word card while it is owed
            # a word, in its own card or row otherwise.
            def href(piece)
                id = piece["id"]
                open = @reading.builder(piece.dig("builds", "question"))
                return "#q-#{piece.dig("builds", "question")}" if open
                return "#p-#{id}" if owed.include?(id)

                "#piece-#{id}"
            end

            def owed = @owed ||= @reading.owed.map { it["id"] }

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
