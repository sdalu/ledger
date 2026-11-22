# frozen_string_literal: true

require_relative "helpers"
require_relative "raid"
require_relative "raid_assumptions"
require_relative "raid_depends"
require_relative "text"

module LedgerViewer
    module Render
        # The ledger's RAID fold: its Risks (every rated risk, highest
        # first), Assumptions (open first, each with its check and what
        # rests on it), Issues (open questions, blocked and stalled
        # pieces, failing checks, noticed lines) and Dependencies (each
        # unsettled after or by link, each deferred condition).
        class RaidFold
            def initialize(kit)
                @scope = kit.scope
                @reading = kit.reading
            end

            # [the fold's body, how many rows it holds]; nil when none.
            def html
                lists = [["Risks", risks], ["Assumptions", assumptions],
                         ["Issues", issues], ["Dependencies", depends]]
                count = lists.sum { it.last.size }
                return if count.zero?

                body = lists.filter_map { |title, rows| list(title, rows) }
                [%(<div class="raid-fold">#{body.join}</div>), count]
            end

            private

            def list(title, rows)
                return if rows.empty?

                "<h3>#{title} (#{rows.size})</h3>" \
                    "<ul class=\"entries raid-list\">#{rows.join}</ul>"
            end

            # A row: ID's link (to its card) and Markdown after it.
            def said(id, text, cls: "")
                html = @scope.inline("#{link(id)} #{text}")
                %(<li class="#{cls}">#{html}</li>)
            end

            def link(id) = RaidDepends.link(id)

            def risks
                items = @reading.pieces + @reading.questions
                rated = items.filter_map do |item|
                    rating, rest = Text.risk_rating(item.dig("risk", "text"))
                    [rating, item, rest] if rating
                end
                rated.sort_by.with_index { |row, at| [-row.first, at] }
                     .map { risk(*it) }
            end

            # The meter and the risk, then the item it is the risk of.
            def risk(rating, item, rest)
                meter = @scope.partial("ledger/rating", rating:, label: "risk")
                title = @scope.inline("#{link(item["id"])} #{item["title"]}")
                %(<li class="#{Helpers.risk_band(rating)}">#{meter} ) +
                    %(<span class="text">#{@scope.inline(rest)}</span>) +
                    %(<div class="meta">#{title}</div></li>)
            end

            def assumptions = RaidAssumptions.new(@scope, @reading).rows

            def issues
                [*@reading.questions.map { opened(it) },
                 *RaidDepends.flight(@reading).filter_map { piece_issue(it) },
                 *@reading.fails.map { |name, detail| failing(name, detail) },
                 *@reading.scope_lines.map { noticed(it) }]
            end

            def opened(question)
                said(question["id"], "open: #{question["title"]}",
                     cls: "is-fail")
            end

            def noticed(line)
                "<li>#{@scope.inline(line.sub(/\A- /, ""))}</li>"
            end

            # 'P2 blocked: title', 'P3 stalled 2 h: title'.
            def piece_issue(piece)
                found = Raid.issues(piece).grep(/\A(?:blocked|stalled)/)
                return if found.empty?

                said(piece["id"], "#{found.join(" · ")}: #{piece["title"]}",
                     cls: "is-fail")
            end

            def failing(name, detail)
                text = @scope.inline(detail.to_s)
                %(<li class="is-fail">#{@scope.chip(name)} ) +
                    %(<span class="text">#{text}</span></li>)
            end

            def depends
                RaidDepends.of(@reading).map { |id, what| said(id, what) }
            end
        end
    end
end
