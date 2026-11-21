# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # The goal blocks: the latest is what the work is now, with the
        # session's title, short and context first and the user's words
        # folded beneath; the earlier ones are its history.
        class Goals
            PARTS = %w[title short context].freeze

            def initialize(scope, blocks, lid)
                @scope = scope
                @blocks = blocks
                @lid = lid
            end

            # The goals as the page shows them, "" when there are none.
            def html(goals)
                last = goals.length - 1
                shown = goals.each_with_index.map do |goal, at|
                    block(goal, at == last ? "#{@lid}-goal-words" : "")
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

            def block(goal, key)
                opened = !(goal["title"] || goal["short"])
                @scope.partial(
                    "ledger/goal",
                    { parts: parts(goal), key:, opened:, said: said(goal),
                      words: @blocks.html(goal["quote"]) }
                )
            end

            # The paragraphs the session wrote, each with its class.
            def parts(goal)
                PARTS.filter_map do |key|
                    text = goal[key]
                    next if text.nil? || text.empty?

                    text = key == "title" ? Text.escape(text) : inline(text)
                    %(<p class="goal-#{key}">#{text}</p>)
                end
            end

            def inline(text) = @scope.inline(text)

            # 'In your words, revised 2026-11-11'.
            def said(goal)
                "In your words, #{"revised " if goal["revised"]}#{goal["date"]}"
            end
        end
    end
end
