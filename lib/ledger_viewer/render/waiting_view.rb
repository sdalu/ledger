# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # What the script needs to show the waiting cards sorted by risk
        # and filtered by it: each card of Waiting on you, and its row in
        # the side list, carries its rating (data-risk, absent when it has
        # none) and its place in the oldest-first order (data-wait-order).
        module WaitingView
            module_function

            # The rating of an item waiting on the user, or nil: a piece's
            # work risk, the number its card shows, a question's risk.
            def rating(item)
                return item["work_risk"] if item.key?("work_risk")

                Text.risk_rating(item.dig("risk", "text").to_s).first
            end

            # ' data-risk="7" data-wait-order="3"' for the item at AT in
            # the page's order.
            def attrs(item, at)
                risk = rating(item)
                %(#{%( data-risk="#{risk}") if risk} data-wait-order="#{at}")
            end

            # HTML, the card or row of an item, its first tag marked.
            def mark(html, item, at)
                html.sub("<li") { "<li#{attrs(item, at)}" }
            end
        end
    end
end
