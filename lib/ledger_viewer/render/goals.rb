# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # The goal blocks: the latest is what the work is now, with the
        # session's title, short and context first and the user's words
        # folded beneath; the earlier ones are its history. goal_block()
        # of ledger-serve.py.
        class Goals
            PARTS = [%w[Title title], ["In short", "short"],
                     %w[Context context]].freeze
            HEADING = /\AGoal \((\d{4}-\d{2}-\d{2})(, revised)?/

            def initialize(scope, blocks, lid)
                @scope = scope
                @blocks = blocks
                @lid = lid
            end

            # The goals as the page shows them, "" when there are none.
            def html(goals)
                last = goals.length - 1
                shown = goals.each_with_index.map do |goal, at|
                    block(*goal, at == last ? "#{@lid}-goal-words" : "")
                end
                return "" if shown.empty?

                shown.last + history(shown[0...-1])
            end

            private

            def history(earlier)
                return "" if earlier.empty?

                @scope.partial(
                    "ledger/goal_history",
                    { lid: @lid, count: earlier.length,
                      blocks: earlier.reverse }
                )
            end

            def block(heading, meta, quote, key)
                opened = !(meta.key?("Title") || meta.key?("In short"))
                @scope.partial(
                    "ledger/goal",
                    { parts: parts(meta), key:, opened:, said: said(heading),
                      words: @blocks.html(quote) }
                )
            end

            # The paragraphs the session wrote, each with its class.
            def parts(meta)
                PARTS.filter_map do |key, cls|
                    text = meta[key]
                    next if text.nil? || text.empty?

                    text = cls == "title" ? Text.escape(text) : inline(text)
                    %(<p class="goal-#{cls}">#{text}</p>)
                end
            end

            def inline(text) = @scope.inline(text)

            # 'Goal (2026-11-11, revised, verbatim)' said as 'In your
            # words, revised 2026-11-11'.
            def said(heading)
                found = HEADING.match(heading)
                return "In your words (#{heading})" unless found

                "In your words, #{"revised " if found[2]}#{found[1]}"
            end
        end
    end
end
