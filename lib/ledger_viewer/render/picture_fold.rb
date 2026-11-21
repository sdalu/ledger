# frozen_string_literal: true

require_relative "clock"

module LedgerViewer
    module Render
        # The fold that asks the session for a picture on a card that has
        # none, a question's or a piece's, and a line per picture asked
        # and not filed; no fold while one is.
        class PictureFold
            # The kinds offered, the session's pick first, as the user
            # reads them.
            KINDS = { "any" => "any: the session picks the cheapest that " \
                               "settles it",
                      "text" => "text: a text figure",
                      "svg" => "svg",
                      "screenshot" => "screenshot",
                      "page" => "page: a working web page" }.freeze

            def initialize(scope, lid, token, reading)
                @scope = scope
                @lid = lid
                @token = token
                @reading = reading
            end

            # A question's: offered while it has no picture placed and
            # none pending.
            def question(question)
                html(question["id"], "q", question["pictures"].empty?)
            end

            # A piece's, on the card PLACE names ("p" its word card,
            # "piece" its card under Unfinished pieces): offered while
            # neither side is placed.
            def piece(piece, place)
                html(piece["id"], place, piece.fetch("pictures", []).empty?)
            end

            private

            def html(ref, place, bare)
                asked = @reading.unfiled_on(ref).select { it["picture"] }
                return "" if asked.empty? && !bare

                @scope.partial(
                    "ledger/picture",
                    { lid: @lid, token: @token, ref:, fid: "#{place}-#{ref}",
                      lines: asked.map { line(it) }, open: asked.empty?,
                      kinds: KINDS }
                )
            end

            def line(entry)
                at = Clock.clock((entry["at"] || "").to_s)
                sent = at.empty? ? "" : ", sent #{at}"
                "picture asked: #{entry["id"]}#{sent} · awaiting filing"
            end
        end
    end
end
