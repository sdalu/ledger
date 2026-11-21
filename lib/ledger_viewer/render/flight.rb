# frozen_string_literal: true

require_relative "clock"
require_relative "entry"
require_relative "links"
require_relative "order"
require_relative "sectioned"
require_relative "serving"
require_relative "say_form"
require_relative "status"
require_relative "text"
require_relative "why"

module LedgerViewer
    module Render
        # What remains to be done on the page: the unfinished pieces, the
        # order to propose for the planned ones, the criteria not met yet
        # and the shape checks failing. The part of render_ledger() after
        # Being prepared.
        class Flight
            include Sectioned

            NONE = "No piece planned, out or blocked."
            ALL_MARKED = "Every criterion is marked."
            EVIDENCE = / — evidence:\z/

            def initialize(kit)
                @kit = kit
                @scope = kit.scope
                @reading = kit.reading
                @entry = Entry.new(@scope)
                @serving = Serving.new(@scope, @reading)
            end

            def html
                pieces = @reading.flight.map { piece(it) }
                [section("Unfinished pieces", pieces, "flight", empty: NONE),
                 Order.new(@kit).html,
                 section("Criteria not met yet", unmet, "criteria",
                         empty: ALL_MARKED),
                 section("Shape checks failing", fails, "checks")].join
            end

            private

            # A deferred piece's meta opens with what it waits on.
            def fields(piece)
                found = Links.fields(piece, @reading.settled)
                condition = piece["until"] or return found

                meta = ["until #{condition}", found[:meta]].reject(&:empty?)
                found.merge(meta: meta.join(" · "))
            end

            def piece(piece)
                sent = @reading.sent_words[piece["id"]]
                return line(piece, sent) if sent && !piece["awaits"].empty?

                dropped = @reading.unfiled_on(piece["id"])
                                  .find { it["word"] == "drop" }
                card(piece, dropped)
            end

            # The user's word on it is sent: that word decides it, so the
            # piece shrinks to one line leading to its card in Sent.
            def line(piece, sent)
                @scope.partial(
                    "ledger/flight_line",
                    { id: piece["id"], status: piece["status"], sent:,
                      title: piece["title"] }
                )
            end

            # A card like a question's: the id and status, the title and
            # the drop in one head; `piece-` because `p-` is the piece's
            # word card.
            def card(piece, dropped)
                id = piece["id"]
                extra = dropped ? "" : @kit.word.drop(id)
                head = @entry.html(**fields(piece), **card_head(piece),
                                   extra:).delete_suffix("</li>")
                "#{head}#{comment(piece)}#{drop(dropped)}</li>"
            end

            def card_head(piece)
                tone = piece["status"] == "blocked" ? "is-fail" : "is-flight"
                { cls: "#{tone} is-card", tag: piece["id"],
                  text: piece["title"], card: true, state: piece["status"],
                  detail: piece["detail"].to_s,
                  kase: @kit.cases.facets(piece),
                  anchor: "piece-#{piece["id"]}",
                  why: Why.icon(@kit.lid, piece["id"]),
                  tag_tip: Status.tip(piece) }
            end

            def comment(piece)
                return "" unless piece["status"] == "planned"

                id = piece["id"]
                spec = SayForm::BLANK.with(ref: id,
                                           label: "Your comment on #{id}")
                form = @kit.say.html(spec)
                @scope.partial("ledger/flight_comment",
                               lid: @kit.lid, id:, form:)
            end

            # A drop asked and not filed yet is said.
            def drop(entry)
                return "" unless entry

                @scope.partial("ledger/flight_drop",
                               id: entry["id"], receipt: Clock.receipt(entry))
            end

            # The fold's summary says "evidence from", so the criterion's
            # own empty marker goes.
            def unmet
                @reading.unmet.map do |criterion|
                    meta, fold = @serving.of(criterion)
                    text = Reading.criterion(criterion)
                    text = text.sub(EVIDENCE, "") unless fold.empty?
                    @entry.html(cls: "is-flight", tag: criterion["id"], text:,
                                meta:, fold:, anchor: "crit-#{criterion["id"]}")
                end
            end

            def fails
                @reading.failing.map do |name, detail|
                    text = detail.to_s.empty? ? "fails" : detail
                    @entry.html(cls: "is-fail", tag: name, text:)
                end
            end
        end
    end
end
