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
            def link(scope, id, href, tip)
                if tip.empty?
                    return %(<a class="id-link" href="#{href}">) +
                           "#{scope.chip(id)}</a>"
                end

                attrs, box = scope.tip(tip)
                %(<a class="id-link" href="#{href}"#{attrs}>) +
                    "#{scope.chip(id)}</a>#{box}"
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
