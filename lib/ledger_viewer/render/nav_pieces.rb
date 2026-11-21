# frozen_string_literal: true

require_relative "reading"
require_relative "terms"
require_relative "text"

module LedgerViewer
    module Render
        # A line of the side list for an unfinished piece: its title, id
        # and a line of status, coloured by whose turn it is.
        class NavPieces
            def initialize(kit)
                @scope = kit.scope
                @reading = kit.reading
            end

            def item(piece)
                line, state = turn(piece)
                title = Text.shorten(piece["title"], 60)
                id = piece["id"]
                [%(<li class="#{state} is-piece"><a href="#piece-#{id}">),
                 %(<span class="what">#{Text.escape(title)}</span>),
                 @scope.chip(id),
                 %(<span class="status">#{Text.escape(line)}</span>),
                 "</a></li>"].join
            end

            private

            # [the status line, the colour].
            def turn(piece)
                status = piece["status"]
                sent = @reading.sent_words[piece["id"]]
                return quiet(piece, status) if piece["awaits"].empty? && !sent
                return [owing(piece, status), "is-ask"] unless sent

                ["#{status} · your #{sent["word"]} sent, awaiting filing",
                 "is-flight"]
            end

            def owing(piece, status)
                "#{status} · awaits your " \
                    "#{Terms.awaits_label(Reading.words(piece))}"
            end

            def quiet(piece, status)
                case status
                when "blocked" then %w[blocked is-fail]
                when "deferred"
                    ["deferred · until #{piece["until"]}", "is-flight"]
                when "out", "back" then [with(piece, status), "is-flight"]
                else [after(piece, status), "is-flight"]
                end
            end

            def with(piece, status)
                route = piece["route_text"].to_s.delete_prefix("peer: ")
                who = route.split(",").first.to_s
                who.empty? ? status : "#{status} · with #{who}"
            end

            def after(piece, status)
                waiting = piece["after"].reject { settled?(it) }
                return status if waiting.empty?

                "#{status} · after #{waiting.join(", ")}"
            end

            def settled?(id) = @reading.settled.fetch(id, false)
        end
    end
end
