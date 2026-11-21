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
            # the page's order: the questions to answer, then the pieces
            # owed a word.
            def self.cards(reading)
                asked = reading.to_answer.map do |question|
                    ["q-#{question["id"]}", question["title"]]
                end
                asked + owed(reading)
            end

            def self.owed(reading)
                sent = reading.sent_words
                reading.owed.reject { sent.key?(it["id"]) }.map do |piece|
                    ["p-#{piece["id"]}", piece["title"]]
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
