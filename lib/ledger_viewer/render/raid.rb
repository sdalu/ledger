# frozen_string_literal: true

require_relative "helpers"
require_relative "links"
require_relative "text"
require_relative "work_risk"

module LedgerViewer
    module Render
        # RAID on one entry: the risk, the assumptions it rests on, its
        # issues and its dependencies, as one compact line under a piece's
        # or a question's case, each part left out when it says nothing.
        class Raid
            # The assumptions in the order the fold lists them.
            STATES = %w[open confirmed refuted].freeze
            # The statuses in flight whose risk not rated goes unsaid.
            UNSTAKED = %w[planned deferred].freeze

            def initialize(scope, reading)
                @scope = scope
                @reading = reading
            end

            # A piece's line; FLIGHT says it is in flight, where a risk not
            # rated is said, except on a planned or deferred piece awaiting
            # no word: nothing is at stake there until it goes out.
            def piece(piece, flight: false)
                unrated = flight && (!UNSTAKED.include?(piece["status"]) ||
                                     piece["awaits"].any?)
                line([risk(WorkRisk.text(piece), unrated, "work"),
                      assumed(piece), issues(piece),
                      depends(Links.forward(piece, @reading)), decided(piece)])
            end

            def question(question)
                line([risk(question.dig("risk", "text").to_s, false, "risk"),
                      assumed(question),
                      question_issues(question),
                      depends(question_links(question)), decided(question)])
            end

            # 'blocked', 'stalled 2 h', 'ready, not sent for 3 h',
            # 'returned 2: depth, unrecorded'.
            def self.issues(piece)
                causes = piece["returns"].map { it["cause"] }
                [("blocked" if piece["status"] == "blocked"),
                 (stalled(piece) if piece["stalled"]),
                 (unsent(piece) if piece["unsent"]),
                 ("returned #{causes.size}: #{causes.join(", ")}" if
                     causes.any?)].compact
            end

            # 'stalled 2 h': how long since an event last touched it.
            def self.stalled(piece)
                waited = Ledger::Text.waited(piece["touched_at"].to_s)
                waited.empty? ? "stalled" : "stalled #{Age.of(waited)}"
            end

            # 'ready, not sent for 2 days': how long it has been ready.
            def self.unsent(piece)
                waited = Ledger::Text.waited(piece["ready_since"].to_s)
                said = "ready, not sent"
                waited.empty? ? said : "#{said} for #{Age.of(waited)}"
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

            # The meter, LABEL N/10, and what is at stake; with UNRATED, a
            # risk not rated is said.
            def risk(text, unrated, label)
                rating, rest = Text.risk_rating(text)
                return unrated(text, unrated) unless rating

                meter = @scope.partial("ledger/rating", rating:, label:)
                said = rest.empty? ? "" : " #{@scope.inline(rest)}"
                part("risk #{Helpers.risk_band(rating)}", "#{meter}#{said}")
            end

            def unrated(text, said)
                unless Text.strip(text).empty?
                    return part("risk", "risk: #{@scope.inline(text)}")
                end
                return "" unless said

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

            # 'waiting 3 h', 'answered by P16 (stalled 2 h)'.
            def question_issues(question)
                said = Links.question_issues(question, @reading.pieces,
                                             Raid.method(:stalled))
                said.empty? ? "" : part("issues", @scope.inline(said))
            end

            # 'decided in X2, X5', each linked to its row in the record.
            def decided(item)
                said = Links.decided(item["id"], @reading)
                said ? part("decided", @scope.inline(said)) : ""
            end

            # 'answered by P5' while that piece is not settled and not
            # stalled (the issues part says it then), 'see F2'.
            def question_links(question)
                [Links.answering(question, @reading.pieces),
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
