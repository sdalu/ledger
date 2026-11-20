# frozen_string_literal: true

require_relative "terms"
require_relative "text"

module LedgerViewer
    module Render
        # The ledger items a question names with `— see:`, spelled out
        # under it: refs_fold() and ref_html() of ledger-serve.py.
        class Refs
            # `menu.css:28`, `home.css:789-794`: a place in the code.
            SPOT = %r{(?u)(?<![\w/])
                      ([\w.-]+(?:/[\w.-]+)*\.[A-Za-z]\w*:\d+(?:[-–]\d+)?)}x
            # A coded entry of a list: `V1 radii by role (…)`, `S4 …`.
            ENTRY = /\A([A-Z][A-Za-z]?\d+[a-z]?)[[:space:]]+(.*)\z/m
            LEAD = /(?u)\A(.*?:)[[:space:]]+(?=[A-Z][A-Za-z]?\d+\b)(.*)\z/m
            KIND_TITLE = { "fact" => "Fact", "constraint" => "Constraint",
                           "criterion" => "Criterion",
                           "piece" => "Piece" }.freeze

            def initialize(scope) = @scope = scope

            # The fold under a question, or "".
            def fold(text, refs)
                seen = Terms.link_ids("see", Terms.split_fields(text)[1]
                                                  .fetch("see", "")) || []
                ids = seen.select { refs.key?(it) }
                return "" if ids.empty?

                rows = ids.map { "<li>#{html(it, *refs[it])}</li>" }
                @scope.partial("ledger/refs", ids:, rows:)
            end

            # A ledger item as the card explains it: what it is and where
            # it comes from on one line, then its text; a coded list one
            # entry per row.
            def html(id, kind, line)
                body = line.include?(": ") ? line.partition(": ").last : line
                body, where = whence(kind, body)
                head = head(id, kind, where)
                parts = split(body).map { Text.strip(it) }.reject(&:empty?)
                return "#{head}<p>#{marked(body)}</p>" if parts.length < 3

                head + list(parts)
            end

            private

            def head(id, kind, where)
                @scope.partial(
                    "ledger/ref_head",
                    { id:, where:, title: KIND_TITLE.fetch(kind, kind),
                      spot: marked(where) }
                )
            end

            # Text drawn by inline(), its places in the code in monospace.
            def marked(text) = spots(@scope.inline(text))

            def whence(kind, body)
                return [body, ""] unless %w[fact constraint].include?(kind)
                return [body, ""] unless body.include?(" — ")

                before, _, after = body.rpartition(" — ")
                [before, after]
            end

            def list(parts)
                intro = ""
                if (found = LEAD.match(parts.first))
                    intro = "<p>#{marked(found[1])}</p>"
                    parts[0] = found[2]
                end
                "#{intro}<ul class=\"entries-list\">" \
                    "#{parts.map { row(it) }.join}</ul>"
            end

            def row(part)
                found = ENTRY.match(part)
                return "<li>#{marked(part)}</li>" unless found

                "<li><strong>#{Text.escape(found[1])}</strong> " \
                    "#{marked(found[2])}</li>"
            end

            def spots(html) = html.gsub(SPOT, '<code>\1</code>')

            # TEXT cut at "; " outside brackets: `(a.md; b)` stays one.
            def split(text)
                depth = 0
                cuts = []
                text.each_char.with_index do |char, at|
                    depth += 1 if "([".include?(char)
                    depth = [depth - 1, 0].max if ")]".include?(char)
                    cuts << at if depth.zero? && text[at, 2] == "; "
                end
                pieces(text, cuts)
            end

            def pieces(text, cuts)
                from = 0
                found = cuts.map do |at|
                    text[from...at].tap { from = at + 2 }
                end
                found << text[from..]
            end
        end
    end
end
