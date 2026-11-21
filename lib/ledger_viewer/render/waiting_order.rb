# frozen_string_literal: true

module LedgerViewer
    module Render
        # What waits on the user, in one order: the questions to answer
        # and the pieces whose word is not sent, the oldest wait first by
        # the index queue's rule (WaitingOrder.key), ties in the ledger's
        # order, questions before words. This is where the order is
        # computed: the index queue sorts by the same key, and the ledger
        # page's head (its next step), Waiting on you, the side list and
        # the next card after a send all read waiting_on_you. Mixed into
        # Reading.
        module WaitingOrder
            # The sort key of a wait that began at SINCE (ISO, or ""):
            # the undated after the dated, the oldest first.
            def self.key(since)
                [since.empty? ? 1 : 0,
                 Ledger::Text.local_time(since) || Time.at(0)]
            end

            # Whether an item waiting on the user is a question (O<n>),
            # not a piece owed a word.
            def self.question?(item) = item["id"].start_with?("O")

            def waiting_on_you
                @waiting_on_you ||= begin
                    items = unanswered.map { [asked.fetch(it["id"], ""), it] } +
                            owing.map { [word_since(it), it] }
                    sorted = items.each_with_index.sort_by do |(since, _), at|
                        [*WaitingOrder.key(since), at]
                    end
                    sorted.map { it.first.last }
                end
            end

            # The questions the user can answer now, in the page's order.
            def to_answer = waiting_on_you.select { WaitingOrder.question?(it) }

            # The questions asked of the user and not answered.
            def open_questions = to_answer

            # The pieces whose word the user has not sent, in the page's
            # order.
            def unsent_words
                waiting_on_you.reject { WaitingOrder.question?(it) }
            end

            private

            def unanswered
                questions.select do |q|
                    !q["preparing"] && !sent_answers.key?(q["id"])
                end
            end

            def owing = owed.reject { sent_words.key?(it["id"]) }

            # When the questions and words still owed were first seen.
            def waits
                words = owing.map { word_since(it) }
                (to_answer.filter_map { asked[it["id"]] } + words)
                    .reject(&:empty?)
            end
        end
    end
end
