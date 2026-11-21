# frozen_string_literal: true

require_relative "clock"
require_relative "helpers"
require_relative "text"

module LedgerViewer
    module Render
        # The head of a ledger page: its name, what to do first, when it
        # changed, its details folded, and the four tiles.
        class Head
            def initialize(kit, entry)
                @scope = kit.scope
                @reading = kit.reading
                @lid = kit.lid
                @entry = entry
            end

            def html
                data = @reading
                path = @entry.path
                @scope.partial(
                    "ledger/head",
                    { lid: @lid, nxt: next_step, tiles:,
                      path: Clock.short(path), status: data.status_text,
                      name: Helpers.project_name(@entry.project, path),
                      updated: Clock.updated(data.updated),
                      changed: Helpers.when_text(data.updated) }
                )
            end

            private

            # What to do first: the next question, the next word, or
            # that nothing waits.
            def next_step
                figures = @reading.figures
                question = @reading.to_answer.first
                piece = @reading.unsent_words.first
                return answer(question) if question
                return word(piece) if piece
                return fixed("a", "#waiting", "Review what waits on you") if
                    figures.asks.positive?

                fixed("span", nil, rest(figures))
            end

            def rest(figures)
                return "Nothing waits on you." unless figures.sent.positive?

                "Your answers are sent; nothing else waits on you."
            end

            def fixed(tag, href, text)
                link = href ? %( href="#{href}") : ""
                %(<#{tag} class="next-step"#{link}>#{text}</#{tag}>)
            end

            def answer(question)
                title = long(question["title"])
                id = question["id"]
                fixed("a", "#q-#{id}", "Answer #{id}: #{title}")
            end

            def word(piece)
                words = @scope.words_span(piece, visible: true)
                inner = "#{@scope.chip(piece["id"])}Your word: " \
                        "#{long(piece["title"])}#{words}"
                fixed("a", "#p-#{piece["id"]}", inner)
            end

            # A title, cut when long, escaped.
            def long(title) = Text.escape(Text.shorten(title, 90))

            def tiles
                figures = @reading.figures
                @scope.partial("ledger/tiles", lid: @lid, c: figures,
                                               asked: asked(figures))
            end

            # The Waiting-on-you tile's line: how long, and what is not
            # ready.
            def asked(figures)
                parts = [longest(figures), sent(figures.sent),
                         preparing(figures.preparing)].compact
                return parts.join(" · ") unless parts.empty?

                figures.asks.positive? ? "" : "nothing asked"
            end

            def longest(figures)
                return unless figures.asks.positive? && !figures.waits.empty?

                first = figures.waits.min_by { Text.local_time(it) }
                "longest #{Text.waited(first)}"
            end

            def preparing(count)
                "#{count} being prepared" if count.positive?
            end

            def sent(count)
                "#{count} answer#{"s" if count > 1} sent" if count.positive?
            end
        end
    end
end
