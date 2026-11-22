# frozen_string_literal: true

require "json"

require "ledger/abandon"
require "ledger/commands/stats_assessed"
require "ledger/stats"

module Ledger
    module Commands
        # `stats [PATH] [--json]`: a track record per route, one row per
        # group, over every ledger, live and closed, or one ledger: a live
        # one by its address, any one by L<id>; over every ledger, a last
        # line counts the closed ones, finished and abandoned (Abandon).
        # The dispatches announced get a section of their own, `by
        # assessment` (StatsAssessed).
        # Reads only: no event, no beat.
        class Stats < CLI::Command
            USAGE = "[PATH]"
            SUMMARY = "a track record per route over every ledger or one: " \
                      "pieces, first-pass verified, blocked, ready and " \
                      "unsent, median time out, returns by cause; and by " \
                      "assessment, the dispatches by highest axis and model"
            LEDGER = /\AL([1-9]\d*)\z/
            HEAD = ["route", "pieces", "first-pass", "blocked", "unsent",
                    "out, median", "returns"].freeze

            private

            def flags(parser)
                parser.on("--json", "JSON v1") { @opts[:json] = true }
            end

            def run(path = nil)
                ids = ledgers(path)
                stats = Ledger::Stats.new(journal.db, ids)
                assessed = StatsAssessed.new(
                    Ledger::Stats::Assessments.new(journal.db, ids,
                                                   stats.tracks)
                )
                closed = path ? nil : closed_counts
                return json(stats.groups, assessed, closed) if @opts[:json]

                text(stats.groups, assessed, closed)
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
            def json(groups, assessed, closed)
                @out.puts JSON.generate(
                    schema: Render::Json::SCHEMA, kind: "stats",
                    groups: groups.map { group(it) },
                    assessments: assessed.json, **({ closed: } if closed)
                )
                0
            end

            # The route table, the section by assessment, the closed
            # ledgers last.
            def text(groups, assessed, closed)
                @out.puts table(groups)
                section = assessed.text
                @out.puts "", section if section
                @out.puts closed_line(closed) if closed
                0
            end

            def group(group)
                { route: group.route, pieces: group.pieces,
                  first_pass_verified: group.first_pass_share,
                  blocked_share: group.blocked_share, unsent: group.unsent,
                  median_out_minutes: group.median_out_minutes,
                  returns: group.returns }
            end

            # The groups as a table (StatsTable).
            def table(groups)
                StatsTable.text([HEAD, *groups.map { cells(it) }])
            end

            def cells(group)
                [group.route, group.pieces.to_s, first_pass(group),
                 "#{group.blocked} #{percent(group.blocked_share)}",
                 group.unsent.to_s,
                 out(group.median_out_minutes),
                 StatsTable.returns(group.returns)]
            end

            def out(minutes) = minutes ? format("%.1f min", minutes) : "-"

            def first_pass(group)
                share = group.first_pass_share or return "-"

                "#{group.first_pass}/#{group.verified} #{percent(share)}"
            end

            def percent(share) = "#{(share * 100).round}%"
        end
    end
end
