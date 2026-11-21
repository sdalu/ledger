# frozen_string_literal: true

require_relative "reading"

module LedgerViewer
    module Render
        # What a receipt ends with: a link to the first card still
        # waiting on the user, or the line saying none does.
        class NextWaiting
            NONE = '<p class="next-waiting is-none">Nothing else waits ' \
                   "on you</p>"

            # [[anchor, title]]: the cards still waiting on the user, in
            # the page's order, the oldest wait first.
            def self.cards(reading)
                reading.waiting_on_you.map do |item|
                    kind = WaitingOrder.question?(item) ? "q" : "p"
                    ["#{kind}-#{item["id"]}", item["title"]]
                end
            end

            def initialize(scope, reading)
                @scope = scope
                @reading = reading
            end

            def html
                first = self.class.cards(@reading).first
                return NONE unless first

                @scope.partial("ledger/next_waiting", anchor: first[0],
                                                      title: first[1])
            end
        end
    end
end
