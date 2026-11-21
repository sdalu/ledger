# frozen_string_literal: true

require_relative "helpers"
require_relative "links"
require_relative "text"

module LedgerViewer
    module Render
        # RAID on one entry: the risk, the assumptions it rests on, its
        # issues and its dependencies, as one compact line under a piece's
        # or a question's case, each part left out when it says nothing.
        class Raid
            # The assumptions in the order the fold lists them.
            STATES = %w[open confirmed refuted].freeze

            def initialize(scope, reading)
                @scope = scope
                @reading = reading
            end

            # A piece's line; FLIGHT says it is in flight, where a risk not
            # rated is said.
            def piece(piece, flight: false)
                line([risk(piece, flight), assumed(piece), issues(piece),
                      depends(piece_links(piece))])
            end

            def question(question)
                line([risk(question, false), assumed(question),
                      depends(question_links(question))])
            end

            # 'blocked', 'stalled 2 h', 'returned 2: depth, unrecorded'.
            def self.issues(piece)
                causes = piece["returns"].map { it["cause"] }
                [("blocked" if piece["status"] == "blocked"),
                 (stalled(piece) if piece["stalled"]),
                 ("returned #{causes.size}: #{causes.join(", ")}" if
                     causes.any?)].compact
            end

            # 'stalled 2 h': how long since an event last touched it.
            def self.stalled(piece)
                waited = Text.waited(piece["touched_at"].to_s)
                waited.empty? ? "stalled" : "stalled #{waited}"
            end

            private

            def line(parts)
                parts = parts.reject(&:empty?)
                return "" if parts.empty?

                %(<p class="raid">#{parts.join}</p>)
            end

            def part(key, html)
                %(<span class="raid-part #{key}">#{html}</span>)
            end

            # The meter and what is at stake; a risk not rated is said
            # only for a piece in flight.
            def risk(item, flight)
                text = item.dig("risk", "text").to_s
                rating, rest = Text.risk_rating(text)
                return unrated(text, flight) unless rating

                meter = @scope.partial("ledger/rating", rating:)
                said = rest.empty? ? "" : " #{@scope.inline(rest)}"
                part("risk #{Helpers.risk_band(rating)}", "#{meter}#{said}")
            end

            def unrated(text, flight)
                unless Text.strip(text).empty?
                    return part("risk", "risk: #{@scope.inline(text)}")
                end
                return "" unless flight

                part("risk is-unrated", "no risk rated")
            end

            # 'rests on A1 (open), A2 (refuted)', each id a chip leading
            # to its row in the RAID fold.
            def assumed(item)
                ids = item["rests_on_assumptions"]
                return "" if ids.empty?

                said = ids.map do |id|
                    state = states.fetch(id)
                    %(<a class="raid-a" href="#raid-#{id}">) +
                        "#{@scope.chip(id)}</a> <span class=\"raid-state " \
                        "is-#{state}\">(#{state})</span>"
                end
                part("assumptions", "rests on #{said.join(", ")}")
            end

            # {A<n> => its state}.
            def states
                @states ||= @reading.assumptions.to_h do |row|
                    [row["id"], row["state"]]
                end
            end

            def issues(piece)
                said = Raid.issues(piece)
                return "" if said.empty?

                part("issues", Text.escape(said.join(" · ")))
            end

            # 'waits for P3' (or its after pieces settled), 'serves D2'.
            def piece_links(piece)
                [(Links.waits(piece, @reading.settled) if piece["after"].any?),
                 ("serves #{Links.ids(piece["for"], "crit")}" if
                     piece["for"].any?)].compact
            end

            # 'answered by P5' while that piece is not settled, 'see F2'.
            def question_links(question)
                by = question["by"]
                by = nil if by && @reading.settled[by]
                [("answered by #{Links.ids([by], "piece")}" if by),
                 ("see #{question["see"].join(", ")}" if
                     question["see"].any?)].compact
            end

            def depends(said)
                return "" if said.empty?

                part("depends", @scope.inline(said.join(" · ")))
            end
        end
    end
end
