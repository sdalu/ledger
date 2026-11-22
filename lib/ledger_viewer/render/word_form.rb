# frozen_string_literal: true

require_relative "clock"
require_relative "terms"
require_relative "text"
require_relative "word_buttons"

module LedgerViewer
    module Render
        # The user's word on a piece (one button per word it awaits, the
        # combined one first), the fold that asks the session to close
        # an item, the one that asks about a question, and the ledger's
        # Close and Abandon.
        class WordForm
            CLOSE = "The session closes it with ledger close: it leaves " \
                    "the list of live ledgers, its history stays in the " \
                    "journal, and its noticed lines are offered to carry. " \
                    "Nothing closes if the ledger changed meanwhile."
            ABANDON = "The session closes it unfinished with ledger close " \
                      "--abandon: the pieces not finished are dropped, the " \
                      "open questions closed, and it leaves the list of " \
                      "live ledgers. Its history stays in the journal."

            DROPS = {
                "P" => "The session marks it dropped and does nothing more " \
                       "with it: no replacement, no commit or deploy of " \
                       "its work, its delegate stopped.",
                "O" => "The session takes it out of Open, records that you " \
                       "dropped it, and does not ask it again."
            }.freeze

            def initialize(scope, lid, token)
                @scope = scope
                @lid = lid
                @token = token
            end

            # The buttons, with the line of what each authorises when the
            # piece carries a scope, and a comment folded below. `prev`
            # is the word sent and not filed, `replaces` the ids it
            # replaces.
            def word(piece, replaces, prev)
                id = piece["id"]
                attrs, box = @scope.tip(
                    "Send the comment alone; #{id} still waits for your word"
                )
                @scope.partial(
                    "ledger/word",
                    { lid: @lid, token: @token, id:, attrs:, box:,
                      replaces: replaces.join(", "), buttons: buttons(piece),
                      text: (prev || {})["text"] || "" }
                )
            end

            # A trash icon opening a reason, optional, and the button, so
            # one stray click drops nothing.
            def drop(ref)
                label = "Ask the session to drop #{Text.escape(ref)} " \
                        "without follow-up"
                attrs, box = @scope.tip(label, hidden: true)
                @scope.partial(
                    "ledger/drop",
                    { lid: @lid, token: @token, ref:, label:, attrs:, box:,
                      says: DROPS.fetch(ref[0, 1], DROPS["O"]) }
                )
            end

            # The fold that asks about question `ref` without answering
            # it, below its answer form, and a line per comment sent and
            # not filed.
            def ask(ref, asked)
                lines = asked.map do |entry|
                    at = Clock.clock((entry["at"] || "").to_s)
                    sent = at.empty? ? "" : ", sent #{at}"
                    "asked: #{entry["id"]}#{sent} · not read by the session yet"
                end
                @scope.partial("ledger/ask",
                               { lid: @lid, token: @token, ref:, lines: })
            end

            # The ledger's Close when its status proposes it, or the
            # close asked and not filed yet; nothing otherwise.
            def close(reading)
                asked = reading.unfiled_on("close").first
                if asked
                    return @scope.partial("ledger/flight_close",
                                          id: asked["id"],
                                          receipt: Clock.receipt(asked))
                end
                return "" unless reading.ready_to_close?
                return "" if reading.unfiled_on("abandon").any?

                @scope.partial("ledger/close",
                               { lid: @lid, token: @token, says: CLOSE })
            end

            # The ledger's Abandon, on any live ledger, or the abandon
            # asked and not filed yet; nothing once a close is asked, which
            # the abandon would contradict.
            def abandon(reading)
                asked = reading.unfiled_on("abandon").first
                if asked
                    return @scope.partial("ledger/flight_abandon",
                                          id: asked["id"],
                                          receipt: Clock.receipt(asked))
                end
                return "" if reading.unfiled_on("close").any?

                @scope.partial("ledger/abandon",
                               { lid: @lid, token: @token, says: ABANDON })
            end

            private

            def buttons(piece) = WordButtons.new(@scope).of(piece)
        end
    end
end
