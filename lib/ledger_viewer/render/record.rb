# frozen_string_literal: true

require_relative "decisions"
require_relative "entry"
require_relative "links"
require_relative "raid_fold"
require_relative "reading"
require_relative "serving"
require_relative "sourced"
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
            DASH = /\A- /

            def initialize(kit)
                @scope = kit.scope
                @reading = kit.reading
                @lid = kit.lid
                @raid = kit.raid
                @raid_fold = RaidFold.new(kit)
                @entry = Entry.new(@scope)
                @serving = Serving.new(@scope, @reading)
                @decisions = Decisions.new(@scope, @entry, @lid)
                @sourced = Sourced.new(@scope, @entry)
            end

            def html
                head = "<h2 id=\"record\">#{@scope.icon("archive")}" \
                       "Done and on record</h2>"
                head + folds.compact.filter_map { fold(*it) }.join
            end

            RAID_TITLE = "Risks, assumptions, issues, dependencies"

            private

            def folds
                reading = @reading
                [raid, ["criteria-met", "Criteria marked", marked],
                 ["pieces-settled", "Pieces verified, kept or dropped",
                  settled],
                 *lines("constraints", "Constraints", reading.constraints),
                 *lines("facts", "Facts", reading.facts),
                 ["decisions", "Decisions", decisions,
                  reading.decisions.length],
                 ["scope", "Out of scope, noticed", plain(reading.scope_lines),
                  reading.scope_lines.length]]
            end

            # The RAID fold, or nil when it would be empty.
            def raid
                body, count = @raid_fold.html
                return unless body

                ["raid", RAID_TITLE, body, count]
            end

            def lines(key, title, list)
                [[key, title, @sourced.html(list), list.length]]
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
                            why: Why.icon(@lid, piece["id"]),
                            fold: @raid.piece(piece),
                            **Links.fields(piece).merge(meta: meta(piece)))
            end

            # The route, and an obsolete piece's replacement as a link to
            # its row.
            def meta(piece)
                by = piece["obsoleted_by"]
                [piece["route_text"],
                 by && "obsoleted by #{Links.ids([by], "piece")}"]
                    .reject { it.to_s.empty? }.join(" · ")
            end
        end
    end
end
