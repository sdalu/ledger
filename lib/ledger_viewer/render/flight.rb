# frozen_string_literal: true

require_relative "clock"
require_relative "entry"
require_relative "flight_row"
require_relative "links"
require_relative "order"
require_relative "sectioned"
require_relative "say_form"
require_relative "status"
require_relative "text"
require_relative "why"

module LedgerViewer
    module Render
        # What remains to be done on the page: the unfinished pieces, the
        # order to propose for the planned ones and the shape checks
        # failing. The part of the page after Being prepared; the
        # criteria not met yet are drawn under the Goal (Unmet).
        class Flight
            include Sectioned

            NONE = "No piece planned, out or blocked."

            def initialize(kit)
                @kit = kit
                @scope = kit.scope
                @reading = kit.reading
                @entry = Entry.new(@scope)
            end

            def html
                pieces = @reading.flight.map { piece(it) }
                [section("Unfinished pieces", pieces, "flight", empty: NONE),
                 Order.new(@kit).html,
                 section("Shape checks failing", fails, "checks")].join
            end

            private

            # A deferred piece's meta opens with what it waits on.
            def fields(piece)
                found = Links.fields(piece)
                condition = piece["until"] or return found

                meta = ["until #{condition}", found[:meta]].reject(&:empty?)
                found.merge(meta: meta.join(" · "))
            end

            def piece(piece)
                sent = @reading.sent_words[piece["id"]]
                return line(piece, sent) if sent && !piece["awaits"].empty?

                return row(piece) if FlightRow.quiet?(piece, @reading)

                dropped = @reading.unfiled_on(piece["id"])
                                  .find { it["word"] == "drop" }
                card(piece, dropped)
            end

            # Nothing to say yet: one row, opening into the card's parts.
            def row(piece)
                detail = piece["detail"].to_s
                body = @entry.body(**fields(piece), kase: kase(piece), detail:)
                body += comment(piece) + @kit.picture.piece(piece, "piece")
                FlightRow.new(@scope, @kit.lid)
                         .html(piece, body, @kit.word.drop(piece["id"]))
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
                picture = @kit.picture.piece(piece, "piece")
                "#{head}#{comment(piece)}#{picture}#{drop(dropped)}</li>"
            end

            def card_head(piece)
                blocked = piece["status"] == "blocked"
                tone = blocked ? "is-fail" : "is-flight"
                detail = blocked ? "" : piece["detail"].to_s
                kase = blocked ? cause(piece) : kase(piece)
                { cls: "#{tone} is-card", tag: piece["id"],
                  text: piece["title"], card: true, state: piece["status"],
                  detail:, kase:, anchor: "piece-#{piece["id"]}",
                  why: Why.icon(@kit.lid, piece["id"]),
                  tag_tip: Status.tip(piece) }
            end

            # A blocked piece's case: what blocks it is the first thing to
            # read, so its detail leads the case, under the title, instead
            # of folding under What it covers.
            def cause(piece)
                detail = piece["detail"].to_s
                return kase(piece) if detail.empty?

                lead = %(<p class="detail cause">#{@scope.inline(detail)}</p>)
                lead + kase(piece)
            end

            # The ties, the facets, then the RAID line.
            def kase(piece)
                facets = @kit.ties.piece(piece) + @kit.cases.facets(piece)
                facets + @kit.raid.piece(piece, flight: true) +
                    @kit.cases.commits(piece)
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

            def fails
                @reading.failing.map do |name, detail|
                    text = detail.to_s.empty? ? "fails" : detail
                    @entry.html(cls: "is-fail", tag: name, text:)
                end
            end
        end
    end
end
