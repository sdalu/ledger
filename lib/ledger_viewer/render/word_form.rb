# frozen_string_literal: true

require_relative "clock"
require_relative "terms"
require_relative "text"

module LedgerViewer
    module Render
        # The user's word on a piece (one button per word it awaits, the
        # combined one first), the fold that asks the session to close
        # an item, and the one that asks about a question.
        class WordForm
            CLOSE = "The session closes it with ledger close: it leaves " \
                    "the list of live ledgers, its history stays in the " \
                    "journal, and its noticed lines are offered to carry. " \
                    "Nothing closes if the ledger changed meanwhile."

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
                label = "Ask the session to close #{Text.escape(ref)} " \
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
                    "asked: #{entry["id"]}#{sent} · awaiting filing"
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

                @scope.partial("ledger/close",
                               { lid: @lid, token: @token, says: CLOSE })
            end

            private

            def buttons(piece)
                names = piece["awaits"].map { it["word"] }
                lines = piece["scope"].to_h { [it["word"], it["text"]] }
                all = names.length > 1 ? [combined(piece["id"], names)] : []
                all + names.map do |word|
                    choice(piece["id"], word, single(word), lines[word])
                end
            end

            def combined(id, names)
                labels = names.map { Terms::WORD_LABEL.fetch(it) }
                inner = @scope.icon("list-checks") + labels.join(" + ")
                choice(id, names.join(", "), inner, nil, "is-combined")
            end

            def single(word)
                @scope.icon(Terms::WORD_ICON.fetch(word)) +
                    Terms::WORD_LABEL.fetch(word)
            end

            def choice(id, value, inner, line, extra = nil)
                said = value.gsub(", ", "-").gsub(" ", "-")
                @scope.partial(
                    "ledger/word_choice",
                    { cls: ["word-choice", extra].compact.join(" "), value:,
                      inner:, line: line || "", wid: "what-#{id}-#{said}" }
                )
            end
        end
    end
end
