# frozen_string_literal: true

require "json"

module Ledger
    module Hooks
        # An inbox entry as `ledger inbox` shows it: a head
        # line `N3 (TIME, answer to O2):` and the entry's lines indented,
        # the user's words verbatim.
        module Entry
            KINDS = { "answer" => "answer to %s",
                      "comment" => "comment on piece %s",
                      "ask" => "comment on question %s, not an answer",
                      "picture" => "picture asked for %<ref>s (%<kind>s)",
                      "order" => "proposed order of the planned pieces",
                      "close" => "the word to close the ledger: " \
                                 "ledger close PATH --take N<n>",
                      "abandon" => "the word to abandon the ledger: " \
                                   "ledger close PATH --abandon --take N<n>",
                      "note" => "note" }.freeze
            # The line boundaries of a splitlines: CR LF, CR, LF and the
            # Unicode ones.
            LINES = /\r\n|[\n\r\v\f\x1c\x1d\x1e\u0085\u2028\u2029]/

            module_function

            def show(row)
                entry = JSON.parse(row[:payload])
                head = "N#{row[:n]} (#{row[:at]}, #{about(entry)}):"
                lines = body(entry)
                "#{head}\n#{(lines.empty? ? [""] : lines)
                              .map { "    #{it}" }.join("\n")}"
            end

            # An entry's ref names its kind; a word on a piece says it, a
            # picture asked on a card its kind.
            def about(entry)
                ref = entry["ref"]
                word = given(entry["word"])
                return "word on #{ref}: #{word}" if word

                kind = given(entry["picture"])
                return format(KINDS["picture"], ref:, kind:) if kind

                format(KINDS.fetch(kind(ref, entry["comment"])), ref)
            end

            # A comment on a question is told from an answer by its
            # `comment` field.
            def kind(ref, comment = nil)
                case ref
                when nil then "note"
                when "order" then "order"
                when "close", "abandon" then ref
                when /\AO\d+\z/ then given(comment) ? "ask" : "answer"
                when /\AP\d+\z/ then "comment"
                end
            end

            def body(entry)
                lines = [*picked(entry), *notes(entry), *picks(entry),
                         *split(entry["text"].to_s)]
                replaces = given(entry["replaces"])
                if replaces
                    lines.unshift("replaces #{replaces.join(", ")}: file " \
                                  "this answer, take them all")
                end
                lines
            end

            def picked(entry)
                [("word: #{entry["word"]}" if given(entry["word"])),
                 ("chose: #{entry["choice"]}" if given(entry["choice"])),
                 ("order: #{entry["order"].join(", ")}" if
                     given(entry["order"]))].compact
            end

            def notes(entry)
                (given(entry["notes"]) || {}).flat_map do |option, note|
                    ["on #{option}:", *split(note.to_s).map { "  #{it}" }]
                end
            end

            def picks(entry)
                (given(entry["picks"]) || {}).map do |item, pick|
                    "#{item}: #{pick}"
                end
            end

            # A trailing boundary ends the last line, as splitlines has it.
            def split(text)
                lines = text.split(LINES, -1)
                lines.pop if lines.last == ""
                lines
            end

            # What the payload's values give: nil, false, ""
            # and an empty list or object are not given.
            def given(value)
                return if value.nil? || value == false
                value unless value.respond_to?(:empty?) && value.empty?
            end
        end
    end
end
