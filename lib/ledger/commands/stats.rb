# frozen_string_literal: true

require "json"

require "ledger/abandon"
require "ledger/stats"

module Ledger
    module Commands
        # `stats [PATH] [--json]`: a track record per route, one row per
        # group, over every ledger, live and closed, or one ledger: a live
        # one by its address, any one by L<id>; over every ledger, a last
        # line counts the closed ones, finished and abandoned (Abandon).
        # Reads only: no event, no beat.
        class Stats < CLI::Command
            USAGE = "[PATH]"
            SUMMARY = "a track record per route over every ledger or one: " \
                      "pieces, first-pass verified, blocked, median time " \
                      "out, returns by cause"
            LEDGER = /\AL([1-9]\d*)\z/
            HEAD = ["route", "pieces", "first-pass", "blocked", "out, median",
                    "returns"].freeze

            private

            def flags(parser)
                parser.on("--json", "JSON v1") { @opts[:json] = true }
            end

            def run(path = nil)
                groups = Ledger::Stats.read(journal.db, ledgers(path))
                closed = path ? nil : closed_counts
                @out.puts @opts[:json] ? json(groups, closed) : text(groups)
                @out.puts closed_line(closed) if closed && !@opts[:json]
                0
            end

            # Over every ledger, the closed ones: {finished:, abandoned:}.
            def closed_counts
                db = journal.db
                ids = db[:ledgers].exclude(closed_at: nil).select_map(:id)
                abandoned = Abandon.ids(db, ids).size
                { finished: ids.size - abandoned, abandoned: }
            end

            def closed_line(counts)
                "closed ledgers: #{counts[:finished]} finished, " \
                    "#{counts[:abandoned]} abandoned"
            end

            def ledgers(path)
                return journal.db[:ledgers].select_map(:id) unless path

                match = LEDGER.match(path)
                row = match ? journal.ledger_by_id(match[1].to_i) : nil
                [(row || journal.ledger(path))[:id]]
            end

            # `closed` only over every ledger.
            def json(groups, closed)
                JSON.generate(schema: Render::Json::SCHEMA, kind: "stats",
                              groups: groups.map { group(it) },
                              **({ closed: } if closed))
            end

            def group(group)
                { route: group.route, pieces: group.pieces,
                  first_pass_verified: group.first_pass_share,
                  blocked_share: group.blocked_share,
                  median_out_minutes: group.median_out_minutes,
                  returns: group.returns }
            end

            # The groups as a table, its columns as wide as their widest
            # cell, the counts right-aligned.
            def text(groups)
                rows = [HEAD, *groups.map { cells(it) }]
                widths = rows.transpose.map { |column| column.map(&:size).max }
                rows.map { line(it, widths) }.join("\n")
            end

            def line(cells, widths)
                cells.zip(widths).each_with_index.map do |(cell, width), index|
                    index == 1 ? cell.rjust(width) : cell.ljust(width)
                end.join("  ").rstrip
            end

            def cells(group)
                [group.route, group.pieces.to_s, first_pass(group),
                 "#{group.blocked} #{percent(group.blocked_share)}",
                 out(group.median_out_minutes), returns(group.returns)]
            end

            def out(minutes) = minutes ? format("%.1f min", minutes) : "-"

            def first_pass(group)
                share = group.first_pass_share or return "-"

                "#{group.first_pass}/#{group.verified} #{percent(share)}"
            end

            def percent(share) = "#{(share * 100).round}%"

            def returns(counts)
                return "-" if counts.empty?

                counts.map { |cause, count| "#{cause} #{count}" }.join(", ")
            end
        end
    end
end
