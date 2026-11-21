# frozen_string_literal: true

require_relative "nav_pieces"
require_relative "terms"
require_relative "text"

module LedgerViewer
    module Render
        # The list beside the page (above it on a narrow one): the words
        # owed, the questions by state, the unfinished pieces, and the
        # other places on the page.
        class Nav
            SIDE = 60
            ICONS = { "Your word" => "stamp", "To answer" => "circle-help",
                      "Sent" => "send", "Being prepared" => "hourglass",
                      "Elsewhere" => "signpost" }.freeze

            def initialize(kit)
                @scope = kit.scope
                @reading = kit.reading
                @lid = kit.lid
                @pieces = NavPieces.new(kit)
            end

            def html
                [words, questions, flight, elsewhere].join
            end

            private

            def title(text) = Text.escape(Text.shorten(text, SIDE))

            def heading(icon, title, count)
                %(<h2>#{@scope.icon(icon)}#{title} ) +
                    %(<span class="count">#{count}</span></h2>)
            end

            def words
                owed = @reading.unsent_words
                return "" if owed.empty?

                rows = owed.map { word(it) }.join
                "#{heading(ICONS["Your word"], "Your word", owed.length)}" \
                    "<ul>#{rows}</ul>"
            end

            def word(piece)
                id = piece["id"]
                [%(<li class="is-ask is-word"><a href="#p-#{id}">),
                 %(<span class="text">#{title(piece["title"])}</span>),
                 @scope.words_span(piece), @scope.chip(id), "</a></li>"].join
            end

            def questions
                [["To answer", "is-ask", @reading.to_answer],
                 ["Sent", "is-flight", @reading.sent_questions],
                 ["Being prepared", "is-flight",
                  @reading.prepared_questions]].map { group(*it) }.join
            end

            def group(name, state, list)
                return "" if list.empty?

                rows = list.map { question(it, state) }.join
                "#{heading(ICONS.fetch(name), name, list.length)}" \
                    "<ul>#{rows}</ul>"
            end

            def flight
                live = @reading.flight
                return "" if live.empty?

                rows = live.map { |piece| @pieces.item(piece) }.join
                [heading(Terms::SECTION_ICON["flight"], "Unfinished pieces",
                         live.length), "<ul>#{rows}</ul>"].join
            end

            # A link to a section that holds nothing is left out.
            def elsewhere
                %(<h2>#{@scope.icon(ICONS["Elsewhere"])}Elsewhere</h2>) +
                    %(<ul class="elsewhere">#{links.join}</ul>) +
                    @scope.partial("shared/legend", key: @lid)
            end

            def links
                [(if @reading.unmet.any?
                      link("#criteria", "criteria", "Criteria not met",
                           @reading.unmet.length)
                  end),
                 (if @reading.said_count.positive?
                      link("#inbox", "inbox", "Your messages",
                           @reading.said_count)
                  end),
                 note, link("#record", "record", "On record", nil)].compact
            end

            def link(href, icon, text, count)
                text = "#{text} · #{count}" if count
                icon = @scope.icon(Terms::SECTION_ICON[icon])
                %(<li><a href="#{href}">#{icon}#{text}</a></li>)
            end

            def note
                icon = @scope.icon("sticky-note")
                %(<li><a href="#say-note">#{icon}Leave a note</a></li>)
            end

            def question(question, state)
                id = question["id"]
                text = title(question["title"])
                %(<li class="#{state}"><a href="#q-#{id}">) +
                    "#{@scope.chip(id)} #{text}</a></li>"
            end
        end
    end
end
