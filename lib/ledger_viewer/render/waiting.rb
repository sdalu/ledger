# frozen_string_literal: true

require_relative "answered"
require_relative "reading"
require_relative "remains"
require_relative "sectioned"
require_relative "terms"
require_relative "text"
require_relative "waiting_view"

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
                @reading.waiting_on_you.each_with_index.map do |item, at|
                    card = if WaitingOrder.question?(item) then @cards.ask(item)
                           else @words.html(item)
                           end
                    WaitingView.mark(card, item, at)
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
                      whole:, refs: ids.join(" "), chips: chips(pieces),
                      symbol: symbol(names),
                      labels: names.map { Terms::WORD_LABEL.fetch(it) } }
                )
            end

            # The group's pieces as id chips, each a link to its card
            # with a tooltip saying what the piece is.
            def chips(pieces)
                pieces.map do |piece|
                    id = piece["id"]
                    attrs, box = @scope.tip(Groups.summary(piece))
                    %(<a class="id-link" href="#p-#{id}"#{attrs}>) +
                        "#{@scope.chip(id)}</a>#{box}"
                end.join(" ")
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

            # What a group's chip tells on hover: the piece's title, its
            # risk rating and the first line of its plan.
            def summary(piece)
                rating, = Text.risk_rating(piece.dig("risk", "text").to_s)
                [piece["title"], ("risk #{rating}/10" if rating),
                 (plan = first_line(piece["plan"])) && "plan: #{plan}"]
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
