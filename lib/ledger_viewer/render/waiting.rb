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
        # answered today; Sent, not read by the session yet; Being prepared.
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

                unread = section("Sent, not read by the session yet", sent,
                                 "sent")
                [waiting(asks, prepared),
                 unread + section("Being prepared", prepared, "preparing")]
            end

            private

            def ask_cards
                @reading.waiting_on_you.map do |item|
                    next @cards.ask(item) if WaitingOrder.question?(item)

                    @words.html(item)
                end
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

            # One word for every set of pieces awaiting the same words.
            def give_all
                owing = @reading.unsent_words
                groups = Groups.of(owing)
                groups.map do |names, pieces|
                    form(names, pieces, pieces.length == owing.length)
                end.join
            end

            def form(names, pieces, whole)
                ids = pieces.map { it["id"] }
                @scope.partial(
                    "ledger/give_all",
                    { lid: @lid, token: @token, count: pieces.length, names:,
                      whole:, refs: ids.join(" "), line: Groups.line(ids),
                      symbol: symbol(names),
                      labels: names.map { Terms::WORD_LABEL.fetch(it) } }
                )
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

        # The pieces owed a word, grouped by the words they await, in
        # the page's order of each group's first piece.
        module Groups
            module_function

            # {[words] => [pieces]} for every set of two or more pieces
            # awaiting the same words, whatever their order; a set with
            # `other` is not one a click can give.
            def of(owing)
                grouped = owing.group_by do |piece|
                    Reading.words(piece).map(&:first).sort
                end
                grouped.reject! do |set, pieces|
                    set.include?("other") || pieces.length < 2
                end
                grouped.values.to_h do |pieces|
                    [Reading.words(pieces.first).map(&:first), pieces]
                end
            end

            # The ids in the order given, a run of consecutive numbers as
            # a range: `P3\u2013P5, P8`.
            def line(ids)
                runs(ids).flat_map do |run|
                    next run if run.length < 3

                    "#{run.first}\u2013#{run.last}"
                end.join(", ")
            end

            def runs(ids)
                ids.slice_when { |a, b| !successor?(a, b) }.to_a
            end

            def successor?(from, to)
                one = from.match(/\A(\D+)(\d+)\z/)
                two = to.match(/\A(\D+)(\d+)\z/)
                one && two && one[1] == two[1] && one[2].to_i + 1 == two[2].to_i
            end
        end
    end
end
