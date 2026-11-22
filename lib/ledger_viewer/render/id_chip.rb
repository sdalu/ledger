# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # An id chip as a link to its item, with a tooltip saying what the
        # item is: the one shape of the group buttons and of a card's ties.
        module IdChip
            module_function

            # The chip of ID linking to HREF, TIP on hover; no tip when
            # TIP is empty.
            # With DONE the chip is muted and ticked.
            def link(scope, id, href, tip, done: false)
                cls = done ? "id-link is-done" : "id-link"
                tick = done ? %(<span aria-hidden="true">✓</span> ) : ""
                attrs, box = tip.empty? ? ["", ""] : scope.tip(tip)
                %(<a class="#{cls}" href="#{href}"#{attrs}>) +
                    "#{tick}#{scope.chip(id)}</a>#{box}"
            end

            # What a chip tells on hover: the item's title, its risk
            # rating and the first line of its plan.
            def summary(item)
                rating, = Text.risk_rating(item.dig("risk", "text").to_s)
                [item["title"], ("risk #{rating}/10" if rating),
                 (plan = first_line(item["plan"])) && "plan: #{plan}"]
                    .compact.join(" · ")
            end

            def first_line(text)
                line = text.to_s.lines.map(&:strip).find { !it.empty? }
                return unless line

                line.length > 80 ? "#{line[0, 79]}…" : line
            end
        end
    end
end
