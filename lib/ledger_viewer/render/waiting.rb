# frozen_string_literal: true

require_relative "answered"
require_relative "reading"
require_relative "remains"
require_relative "sectioned"
require_relative "terms"
require_relative "text"

module LedgerViewer
    module Render
        # The sections of questions and words: Waiting on you, with the
        # one word for every piece that awaits the same, and what was
        # answered today; Sent, awaiting filing; Being prepared.
        class Waiting
            include Sectioned

            NOTHING = "Nothing asked of you."
            BELOW = " Being prepared, below."

            def initialize(kit, cards, words, token)
                @scope = kit.scope
                @reading = kit.reading
                @lid = kit.lid
                @cards = cards
                @words = words
                @token = token
            end

            # [Waiting on you, then Sent and Being prepared]; the first
            # is Remains when nothing is asked or in flight.
            def sections
                asks = ask_cards
                sent = sent_cards
                prepared = @reading.prepared_questions.map do |question|
                    @cards.preparing(question)
                end
                return [Remains.html(@reading), ""] if @reading.settled?

                [waiting(asks, prepared), section("Sent, awaiting filing", sent,
                                                  "sent") +
                    section("Being prepared", prepared, "preparing")]
            end

            private

            def ask_cards
                @reading.open_questions.map { @cards.ask(it) } +
                    @reading.unsent_words.map { @words.html(it) }
            end

            def sent_cards
                @reading.sent_questions.map { @cards.ask(it) } +
                    @reading.owed.select { @reading.sent_words.key?(it["id"]) }
                            .map { @words.html(it) }
            end

            def waiting(asks, prepared)
                empty = prepared.empty? ? NOTHING : "#{NOTHING}#{BELOW}"
                html = section("Waiting on you", asks, "waiting", empty:)
                html = html.sub("</h2>") { "</h2>#{give_all}" } unless
                    asks.empty?
                html + answered
            end

            # One word for every piece waiting, when they all await the
            # same words.
            def give_all
                owing = @reading.unsent_words
                names = shared(owing) or return ""
                @scope.partial(
                    "ledger/give_all",
                    { lid: @lid, token: @token, count: owing.length, names:,
                      refs: owing.map { |piece| piece["id"] }.join(" "),
                      symbol: symbol(names),
                      labels: names.map { |word| Terms::WORD_LABEL.fetch(word) } }
                )
            end

            # The words every one of several pieces awaits, if they are the
            # same and the user can give them with one click.
            def shared(owing)
                sets = owing.map { |piece| Reading.words(piece).map(&:first) }
                            .uniq
                sets.first if owing.length > 1 && sets.length == 1 &&
                              !sets.first.include?("other")
            end

            def symbol(names)
                return "list-checks" unless names.length == 1

                Terms::WORD_ICON.fetch(names.first)
            end

            def answered
                lines = Answered.of(@reading.decisions)
                return "" if lines.empty?

                @scope.partial("ledger/answered", lines:)
            end
        end
    end
end
