# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # The goal blocks: each one still active open, newest first, with
        # the session's title, short and context first and the user's
        # words folded beneath; the done ones folded together under them,
        # newest first, each with its evidence.
        class Goals
            PARTS = %w[title short context].freeze

            def initialize(scope, blocks, lid)
                @scope = scope
                @blocks = blocks
                @lid = lid
            end

            # The goals as the page shows them, "" when there are none.
            def html(goals)
                done, active = goals.reverse.partition { it["done"] }
                shown = active.each_with_index.map do |goal, at|
                    block(goal, at.zero? ? "#{@lid}-goal-words" : "")
                end
                shown.join + finished(done.map { block(it, "") })
            end

            private

            def finished(blocks)
                return "" if blocks.empty?

                @scope.partial(
                    "ledger/goal_done",
                    { lid: @lid, count: blocks.length, blocks: }
                )
            end

            def block(goal, key)
                opened = !(goal["title"] || goal["short"])
                @scope.partial(
                    "ledger/goal",
                    { id: goal["id"], parts: parts(goal), key:, opened:,
                      said: said(goal), words: @blocks.html(goal["quote"]) }
                )
            end

            # The paragraphs the session wrote, each with its class, the
            # evidence of a done block after its short.
            def parts(goal)
                title, short, context = PARTS.map { paragraph(it, goal[it]) }
                [title, short, evidence(goal), context].compact
            end

            def paragraph(key, text)
                return if text.nil? || text.empty?

                text = key == "title" ? Text.escape(text) : inline(text)
                %(<p class="goal-#{key}">#{text}</p>)
            end

            def evidence(goal)
                return unless goal["done"]

                done = inline(goal["done_evidence"])
                %(<p class="goal-evidence">Done: #{done}</p>)
            end

            def inline(text) = @scope.inline(text)

            # 'In your words, revised 2026-11-11'.
            def said(goal)
                "In your words, #{"revised " if goal["revised"]}#{goal["date"]}"
            end
        end
    end
end
