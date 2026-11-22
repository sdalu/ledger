# frozen_string_literal: true

require_relative "reading"

module LedgerViewer
    module Render
        # What a receipt ends with: a link to the first card still
        # waiting on the user, or the line saying none does.
        class NextWaiting
            NONE = '<p class="next-waiting is-none" role="status" ' \
                   'tabindex="-1">Nothing left waiting on you in this ' \
                   "ledger</p>"

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

            # The first card still waiting after the answered card, the
            # one at ANCHOR ("q-O2", "p-P4"), in the page's order; the
            # first of all when none follows, nil when none waits.
            def self.after(reading, anchor)
                cards = cards(reading)
                mark = rank(reading, anchor)
                cards.find { (rank(reading, it[0]) <=> mark) == 1 } ||
                    cards.first
            end

            # Where a card stands in the waiting order. The answered card
            # has left waiting_on_you, so its place is recomputed from the
            # same key (WaitingOrder.key) over its wait's start: the order
            # of waiting_on_you is the page's order, so a card whose rank
            # is greater comes after it on the page. Ties go as there:
            # questions before words, then the ledger's order.
            def self.rank(reading, anchor)
                kind, id = anchor.split("-", 2)
                since, at = kind == "q" ? asked(reading, id) : owed(reading, id)
                [*WaitingOrder.key(since), kind == "q" ? 0 : 1, at]
            end

            # [wait's start, position in the ledger] of a question.
            def self.asked(reading, id)
                [reading.asked.fetch(id, ""),
                 reading.questions.index { it["id"] == id } || 0]
            end

            # The same for a piece owed a word.
            def self.owed(reading, id)
                at = reading.owed.index { it["id"] == id }
                return ["", 0] unless at

                [reading.word_since(reading.owed[at]), at]
            end

            # The link after the card at ANCHOR was answered.
            def html(anchor)
                first = self.class.after(@reading, anchor)
                return NONE unless first

                @scope.partial("ledger/next_waiting", anchor: first[0],
                                                      title: first[1])
            end
        end
    end
end
