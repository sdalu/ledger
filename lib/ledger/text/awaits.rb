# frozen_string_literal: true

module Ledger
    module Text
        # "awaits: commit, deploy" on a piece: the user's word it cannot
        # move without, from a fixed list, or "other (what)" for anything
        # else; and its "scope" lines, "WORD = what it authorises".
        module Awaits
            # start begins a planned piece; the others finish one that is
            # done.
            WORDS        = %w[start commit deploy push merge].freeze
            FINISH_WORDS = %w[commit deploy push merge].freeze
            OTHER        = /\Aother \((.+)\)\z/

            module_function

            # "commit, other (look at the shots)" -> [["commit", ""],
            # ["other", "look at the shots"]], or nil when a word is not
            # one the list knows or an "other" says nothing of what it
            # needs.
            def parse(value)
                out = []
                split(value).each do |part|
                    word = entry(part.strip) or return nil
                    out << word if word != :blank
                end
                out.empty? ? nil : out
            end

            # "commit = merge it | deploy = ship it" -> [["commit",
            # "merge it"], ["deploy", "ship it"]], or nil when a part is not
            # "WORD = what" with both sides filled.
            def scope_words(value)
                pairs = value.split(" | ", -1).map do |part|
                    word, eq, what = part.partition(" = ")
                    return nil if eq.empty? || word.strip.empty? ||
                                  what.strip.empty?

                    [word.strip, what.strip]
                end
                pairs.empty? ? nil : pairs
            end

            def scope_text(pairs)
                pairs.map { |w, what| "#{w} = #{what}" }.join(" | ")
            end

            def label(words)
                words.map do |w, d|
                    w == "other" ? "other (#{d})" : w
                end.join(", ")
            end

            def finish?(word) = FINISH_WORDS.include?(word)

            # One part: nil when unknown, :blank when empty.
            def entry(word)
                return :blank if word.empty?

                if (match = OTHER.match(word)) && !match[1].strip.empty?
                    ["other", match[1].strip]
                elsif WORDS.include?(word)
                    [word, ""]
                end
            end

            # VALUE cut at the commas outside parentheses.
            def split(value)
                depth = 0
                "#{value},".each_char.with_object([+""]) do |ch, parts|
                    depth += 1 if ch == "("
                    depth = [depth - 1, 0].max if ch == ")"
                    if ch == "," && depth.zero?
                        parts << +""
                    else
                        parts.last << ch
                    end
                end[0...-1]
            end
        end
    end
end
