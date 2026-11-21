# frozen_string_literal: true

require_relative "terms"

module LedgerViewer
    module Render
        # What a piece waits for and serves, said as Markdown links to
        # the cards and criteria on the page.
        module Links
            module_function

            # 'P3, P5' as links to their cards: `piece-P3`, `crit-D2`.
            def ids(ids, kind)
                ids.map { "[#{it}](##{kind}-#{it})" }.join(", ")
            end

            # The meta line's parts for `piece`; `settled` is {id =>
            # whether that piece is settled}.
            def meta(piece, settled)
                out = []
                out << waits(piece, settled) unless piece["after"].empty?
                out << "for #{ids(piece["for"], "crit")}" unless
                    piece["for"].empty?
                out
            end

            # The meta, evidence and done fields of a piece's row.
            def fields(piece, settled)
                meta = ([piece["route_text"]] + meta(piece, settled))
                       .reject { it.to_s.empty? }.join(" · ")
                { meta:, evidence: piece["evidence"].to_s,
                  done: piece["done_when"].to_s }
            end

            def waits(piece, settled)
                after = piece["after"]
                waiting = after.reject { settled.fetch(it, false) }
                return "waits for #{ids(waiting, "piece")}" unless
                    waiting.empty?

                ready = piece["status"] == "planned" ? "ready: " : ""
                "#{ready}after #{ids(after, "piece")}, settled"
            end

            # ['verified', 'kept'] -> '2 pieces: 1 verified, 1 kept': the
            # verified and the kept first, every other status after, in the
            # order seen.
            def counts(statuses)
                tally = statuses.tally
                keys = tally.keys.sort_by.with_index do |key, at|
                    [key == "verified" ? 0 : 1, key == "kept" ? 0 : 1, at]
                end
                total = statuses.length
                "#{total} piece#{"s" unless total == 1}: " +
                    keys.map { "#{tally[it]} #{it}" }.join(", ")
            end
        end
    end
end
