# frozen_string_literal: true

require_relative "clock"
require_relative "reading"
require_relative "terms"
require_relative "text"
require_relative "why"
require_relative "word_evidence"

module LedgerViewer
    module Render
        # The card of a piece that waits on the user's word, and the
        # receipt of the word once sent.
        class WordCards
            def initialize(kit, waiting)
                @kit = kit
                @scope = kit.scope
                @reading = kit.reading
                @waiting = waiting
            end

            def html(piece)
                last = @reading.sent_words[piece["id"]]
                form = form(piece, last)
                needed = below(piece)
                return receipt(piece, last, needed, form) if last

                "#{card(piece)}#{needed}#{form}#{picture(piece)}</li>"
            end

            private

            # The word buttons, the evidence they rest on just above them.
            def form(piece, last)
                prior = @reading.unfiled_on(piece["id"]).select { it["word"] }
                ids = prior.map { it["id"] }
                WordEvidence.html(@scope, piece) +
                    @kit.word.word(piece, ids, last)
            end

            def card(piece)
                @scope.partial(
                    "ledger/card",
                    { cls: "is-ask is-card", anchor: "p-#{piece["id"]}",
                      text: piece["title"], tag: piece["id"],
                      detail: piece["detail"].to_s, meta: meta(piece),
                      kase: kase(piece),
                      extra: @kit.word.drop(piece["id"]),
                      why: Why.icon(@kit.lid, piece["id"]) }
                )
            end

            # The fold that asks for a picture, on the word card.
            def picture(piece) = @kit.picture.piece(piece, "p")

            def kase(piece)
                @kit.ties.piece(piece) + @kit.cases.facets(piece) +
                    @kit.raid.piece(piece)
            end

            def meta(piece)
                since = @reading.word_since(piece)
                waited = Ledger::Text.waited(since)
                wait = "waiting #{Age.of(waited)}, since #{Text.minute(since)}"
                [piece["route_text"], (wait unless waited.empty?)]
                    .reject { it.to_s.empty? }.join(" · ")
            end

            # What the card says under its head: what an other word
            # needs, the piece's before/after or why it has none, and the
            # commits that landed it.
            def below(piece)
                needed(piece) + @kit.mockups.sides(piece) +
                    @kit.cases.commits(piece)
            end

            def needed(piece)
                others = Reading.words(piece).select { it.first == "other" }
                others.map do |_, desc|
                    %(<p class="needed">Needed: #{@scope.inline(desc)}</p>)
                end.join
            end

            def receipt(piece, last, needed, form)
                @scope.partial(
                    "ledger/word_receipt",
                    { id: piece["id"], title: piece["title"], line: line(last),
                      said: said(last),
                      next_waiting: @waiting.html("p-#{piece["id"]}"),
                      lid: @kit.lid, needed:, form: }
                )
            end

            def line(last)
                at = Clock.clock((last["at"] || "").to_s)
                ["You asked: <strong>#{Text.escape(asked(last))}</strong>",
                 (at.empty? ? nil : "sent #{at}"),
                 "not read by the session yet"].compact.join(" · ")
            end

            def asked(last)
                given = last["word"].split(",", -1).map { Text.strip(it) }
                return "Drop without follow-up" if given == ["drop"]

                given.map { Terms::WORD_LABEL.fetch(it, it) }.join(" + ")
            end

            def said(last)
                return "" if Text.strip(last["text"]).empty?

                html = @kit.blocks.html(last["text"])
                @scope.partial("ledger/said", html:)
            end
        end
    end
end
