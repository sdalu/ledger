# frozen_string_literal: true

require_relative "decisions"
require_relative "entry"
require_relative "links"
require_relative "reading"
require_relative "serving"
require_relative "status"
require_relative "terms"
require_relative "text"
require_relative "why"

module LedgerViewer
    module Render
        # Done and on record: the folds holding what is settled, the
        # criteria marked, the pieces closed, the constraints, facts,
        # decisions and what was left out of scope.
        class Record
            CONSTRAINT = /\A- (C\d+): "(.+?)" — (.+?)(?: \((.+)\))?\z/
            FACT = /\A- (F\d+): (.+?) — (\S.*)\z/
            DASH = /\A- /

            def initialize(kit)
                @scope = kit.scope
                @reading = kit.reading
                @lid = kit.lid
                @entry = Entry.new(@scope)
                @serving = Serving.new(@scope, @reading)
                @decisions = Decisions.new(@scope, @entry, @lid)
            end

            def html
                head = "<h2 id=\"record\">#{@scope.icon("archive")}" \
                       "Done and on record</h2>"
                head + folds.filter_map { fold(*it) }.join
            end

            private

            def folds
                reading = @reading
                [["criteria-met", "Criteria marked", marked],
                 ["pieces-settled", "Pieces verified, kept or dropped",
                  settled],
                 *lines("constraints", "Constraints", reading.constraints),
                 *lines("facts", "Facts", reading.facts),
                 ["decisions", "Decisions", decisions,
                  reading.decisions.length],
                 ["scope", "Out of scope, noticed", plain(reading.scope_lines),
                  reading.scope_lines.length]]
            end

            def lines(key, title, list)
                [[key, title, sourced(list), list.length]]
            end

            def fold(key, title, rows, count = rows.length)
                return if rows.empty?

                body = rows.is_a?(String) ? rows : list(rows)
                @scope.partial("ledger/record_fold",
                               { lid: @lid, key:, title: "#{title} (#{count})",
                                 body: })
            end

            def list(rows) = "<ul class=\"entries\">#{rows.join}</ul>"

            # A line of the ledger without its list dash.
            def undashed(line) = line.sub(DASH, "")

            def plain(lines)
                lines.map { @entry.html(text: undashed(it)) }
            end

            def decisions
                @decisions.html(@reading.decisions, @reading.decision_ids)
            end

            def marked
                met = @reading.criteria.select { %w[x -].include?(it["mark"]) }
                met.map { marked_row(it) }
            end

            def marked_row(criterion)
                done = criterion["mark"] == "x"
                meta, fold = @serving.of(criterion)
                @entry.html(
                    cls: done ? "is-done" : "", meta:, fold:,
                    tag: "#{criterion["id"]} #{done ? "met" : "not met"}",
                    text: Reading.criterion(criterion),
                    anchor: "crit-#{criterion["id"]}"
                )
            end

            def settled
                shut = @reading.pieces.reject do |piece|
                    Reading::IN_FLIGHT.include?(piece["status"])
                end
                shut.map { settled_row(it) }
            end

            def settled_row(piece)
                @entry.html(cls: "is-done", tag: piece["id"],
                            text: Reading.what(piece), state: Status.of(piece),
                            tag_tip: Status.tip(piece),
                            anchor: "piece-#{piece["id"]}",
                            fold: Why.link(@lid, piece["id"]),
                            **Links.fields(piece, @reading.settled))
            end

            # Constraint and fact rows as their parts: the id chip, the
            # words, then a muted line with where it was said or found; a
            # line that does not parse is drawn as the plain text.
            def sourced(lines)
                lines.map do |line|
                    if (found = CONSTRAINT.match(line))
                        constraint(found)
                    elsif (found = FACT.match(line))
                        fact(found)
                    else
                        @entry.html(text: undashed(line))
                    end
                end
            end

            def constraint(found)
                body = "<q>#{@scope.inline(found[2])}</q>"
                source(found[1], body, found.values_at(3, 4))
            end

            def fact(found)
                body = %(<span class="text">#{@scope.inline(found[2])}</span>)
                source(found[1], body, [found[3]])
            end

            def source(id, body, parts)
                src = parts.reject { it.to_s.empty? }.join(" · ")
                @scope.partial("ledger/sourced", id:, body:, src:)
            end
        end
    end
end
