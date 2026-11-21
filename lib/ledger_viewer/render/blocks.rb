# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # Several lines of Markdown: paragraphs, `-`/`*` and `1.` lists,
        # `>` quotes (nested by recursion), fenced code; each line through
        # inline().
        class Blocks
            ITEM = /\A[[:space:]\x1c-\x1f]*([-*]|\d+[.)])
                    [[:space:]\x1c-\x1f]+(.*)\z/mx
            QUOTE = /\A> ?/

            # scope answers inline(text).
            def initialize(scope)
                @scope = scope
            end

            def html(text)
                @lines = text.gsub("\r\n", "\n").split("\n", -1)
                @out = []
                @para = []
                walk
                flush
                @out.join
            end

            private

            def walk
                at = 0
                at = step(at) while at < @lines.length
            end

            def step(at)
                line = @lines[at]
                return fence(at) if Text.strip(line).start_with?("```")
                return quote(at) if line.start_with?(">")
                return list(at) if ITEM.match?(line)

                Text.strip(line).empty? ? flush : @para << line
                at + 1
            end

            def flush
                return if @para.empty?

                lines = @para.map { @scope.inline(it) }.join("<br>")
                @out << "<p>#{lines}</p>"
                @para.clear
            end

            def numbered?(item) = item[1].match?(/\A\d/)

            def fence(at)
                flush
                stop = at + 1
                stop += 1 until stop >= @lines.length ||
                                Text.strip(@lines[stop]).start_with?("```")
                code = Text.escape(@lines[(at + 1)...stop].join("\n"))
                @out << "<pre><code>#{code}</code></pre>"
                stop + 1
            end

            def quote(at)
                flush
                stop = at
                stop += 1 while stop < @lines.length &&
                                @lines[stop].start_with?(">")
                inner = @lines[at...stop].map { it.sub(QUOTE, "") }.join("\n")
                @out << "<blockquote>#{Blocks.new(@scope).html(inner)}" \
                        "</blockquote>"
                stop
            end

            def list(at)
                flush
                items = run(at)
                tag = numbered?(items.first) ? "ol" : "ul"
                rows = items.map { "<li>#{@scope.inline(it[2])}</li>" }
                @out << "<#{tag}>#{rows.join}</#{tag}>"
                at + items.length
            end

            # The items from `at` that are of one kind, numbered or not.
            def run(at)
                ordered = numbered?(ITEM.match(@lines[at]))
                @lines[at..].map { ITEM.match(it) }.take_while do |item|
                    item && numbered?(item) == ordered
                end
            end
        end
    end
end
