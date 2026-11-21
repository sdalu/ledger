# frozen_string_literal: true

require_relative "helpers"

module LedgerViewer
    module Render
        # The vocabulary the ledger page reads: what a picture is, which
        # words a piece can await, which icon a section has. Plain
        # functions.
        module Terms
            MOCKUP_IMAGES = %w[.svg .png .jpg .jpeg .gif .webp].freeze

            # What the page draws for each word a piece awaits.
            WORD_ICON = { "start" => "play", "commit" => "git",
                          "push" => "git", "merge" => "git",
                          "deploy" => "rocket", "other" => "check" }.freeze
            WORD_LABEL = { "start" => "Start", "commit" => "Commit",
                           "deploy" => "Deploy", "push" => "Push",
                           "merge" => "Merge", "other" => "Done" }.freeze
            # A section's icon, by its anchor; the same on its tile.
            SECTION_ICON = {
                "waiting" => "hand", "sent" => "send",
                "preparing" => "hourglass", "flight" => "list-todo",
                "criteria" => "list-checks", "checks" => "triangle-alert",
                "inbox" => "inbox", "record" => "archive", "goal" => "target"
            }.freeze

            module_function

            # The kind of an inbox entry by its ref and its fields: note,
            # order, close, abandon, answer, ask (a comment on a
            # question), comment, picture, or nil.
            def kind(ref, entry = {})
                case ref
                when nil then "note"
                when "order", "close", "abandon" then ref
                when /\A[OP]\d+\z/ then card_kind(ref, entry)
                end
            end

            # A comment on a question or a picture asked: an entry on a
            # card that answers nothing and gives no word.
            def aside?(entry) = [entry["comment"], entry["picture"]].any?

            def card_kind(ref, entry)
                return "picture" if Helpers.filled?(entry["picture"])
                return "comment" if ref.start_with?("P")

                entry["comment"] ? "ask" : "answer"
            end

            # 'A = keep as is' -> 'A'; an option without a meaning is its
            # own code.
            def option_code(option)
                Text.strip(option.partition(" = ").first)
            end

            def awaits_label(words)
                words.map { |w, d| w == "other" ? "other (#{d})" : w }
                     .join(", ")
            end

            # A file name without its extension, cut at the last dot unless it
            # leads the name.
            def stem(base)
                at = base.rindex(".")
                at && base[0...at].match?(/[^.]/) ? base[0...at] : base
            end
        end
    end
end
