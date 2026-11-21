# frozen_string_literal: true

require_relative "pointer"

module LedgerViewer
    module Render
        # Constraint and fact objects as their parts: the id chip, the
        # words, then a muted line with where it was said or found, drawn
        # by its kind (Pointer); free text is drawn as any line is, and a
        # line that does not parse as the plain text.
        class Sourced
            CONSTRAINT = /\A- (C\d+): "(.+?)" — (.+?)(?: \((.+)\))?\z/
            FACT = /\A- (F\d+): (.+?) — (\S.*)\z/
            DASH = /\A- /

            def initialize(scope, entry)
                @scope = scope
                @entry = entry
            end

            def html(rows) = rows.map { row(it) }

            private

            def row(row)
                line = row["line"]
                if (found = CONSTRAINT.match(line)) then constraint(found, row)
                elsif (found = FACT.match(line)) then fact(found, row)
                else @entry.html(text: line.sub(DASH, ""))
                end
            end

            def constraint(found, row)
                body = "<q>#{@scope.inline(found[2])}</q>"
                src = Pointer.html(row["where"], row["where_kind"])
                source(found[1], body, src || plain(found[3], found[4]))
            end

            def fact(found, row)
                body = %(<span class="text">#{@scope.inline(found[2])}</span>)
                src = Pointer.html(row["pointer"], row["pointer_kind"])
                source(found[1], body, src || plain(found[3]))
            end

            def plain(*parts)
                @scope.inline(parts.reject { it.to_s.empty? }.join(" · "))
            end

            def source(id, body, src)
                @scope.partial("ledger/sourced", id:, body:, src:)
            end
        end
    end
end
