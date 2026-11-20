# frozen_string_literal: true

require_relative "collector"

module LedgerViewer
    module Render
        # The index page: one queue of what waits on the user across
        # every ledger, oldest wait first; then what is the sessions'
        # turn; then the ledgers themselves. render_index() of
        # ledger-serve.py, from the ledgers' dumps.
        class Index
            def initialize(views, scope, page)
                @views = views
                @scope = scope
                @page = page
            end

            # entries: the Ledgers::Entry list; readings: {path => dump
            # Hash or nil}; stamp: Stamp.of(entries).
            def html(entries, readings, stamp)
                found = Collector.new(@scope)
                entries.each { found.add(it, readings[it.path]) }
                queue = queue_of(found.queue)
                body = @scope.partial("index/body", **parts(found, queue))
                @page.html(title: title(queue), body:, stamp:)
            end

            private

            # Stable: ties keep the order the ledgers were found in.
            def queue_of(items)
                items.sort_by { it[0..3] }.map(&:last)
            end

            def title(queue)
                head = "What waits on you"
                queue.empty? ? head : "(#{queue.length}) #{head}"
            end

            def parts(found, queue)
                { summary: summary(found).join(" · "), queue:,
                  noid: found.noid.sort.map(&:last), theirs: found.theirs,
                  rows: found.rows.sort.map(&:last) }
            end

            # The line under the title: what the page counts, in order.
            def summary(found)
                totals = found.totals
                asks, words, sent, prepared = totals.values_at(
                    :asks, :words, :sent, :prepared
                )
                [phrase(asks, "question"), phrase(words, "word", " to give"),
                 ("#{found.noid.length} to review" if found.noid.any?),
                 phrase(sent, "answer", " sent, awaiting filing"),
                 ("#{prepared} being prepared" if prepared.positive?)].compact
            end

            def phrase(count, noun, tail = "")
                return unless count.positive?

                "#{count} #{noun}#{Helpers.plural(count)}#{tail}"
            end
        end
    end
end
