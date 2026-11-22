# frozen_string_literal: true

require_relative "nav_pieces"
require_relative "reading"
require_relative "terms"
require_relative "text"
require_relative "waiting_view"

module LedgerViewer
    module Render
        # The list beside the page (above it on a narrow one): the words
        # owed, the questions by state, the unfinished pieces, and the
        # other places on the page.
        class Nav
            SIDE = 60
            ICONS = { "Sent" => "send", "Being prepared" => "hourglass",
                      "Elsewhere" => "signpost" }.freeze

            def initialize(kit)
                @scope = kit.scope
                @reading = kit.reading
                @lid = kit.lid
                @pieces = NavPieces.new(kit)
            end

            def html
                [waiting, questions, flight, elsewhere].join
            end

            private

            def title(text) = Text.escape(Text.shorten(text, SIDE))

            def heading(icon, title, count)
                %(<h2>#{@scope.icon(icon)}#{title} ) +
                    %(<span class="count">#{count}</span></h2>)
            end

            # The questions to answer and the words owed, in the page's
            # order: the oldest wait first.
            def waiting
                items = @reading.waiting_on_you
                return "" if items.empty?

                rows = items.each_with_index.map do |item, at|
                    asked = WaitingOrder.question?(item)
                    row = asked ? question(item, "is-ask") : word(item)
                    WaitingView.mark(row, item, at)
                end
                icon = Terms::SECTION_ICON["waiting"]
                "#{heading(icon, "Waiting on you", items.length)}" \
                    "<ul>#{rows.join}</ul>"
            end

            def word(piece)
                id = piece["id"]
                [%(<li class="is-ask is-word"><a href="#p-#{id}">),
                 %(<span class="text">#{title(piece["title"])}</span>),
                 @scope.words_span(piece), @scope.chip(id), "</a></li>"].join
            end

            def questions
                [["Sent", "is-flight", @reading.sent_questions],
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
                [%(<li class="#{state} is-question"><a href="#q-#{id}">),
                 %(<span class="text">#{text}</span>), @scope.chip(id),
                 "</a></li>"].join
            end
        end
    end
end
