# frozen_string_literal: true

require "ledger/hooks/ledgers"

module Ledger
    module Hooks
        # The resume view (U5): what a session starting, resuming or
        # compacted needs of its ledgers, at most BUDGET characters shared
        # equally among them. Per ledger, every line as `show` prints it:
        # a pointer line, the status line, every Goal block, Constraints,
        # the open questions, the pieces in flight with `(ready)` or
        # `(stalled)`. Over its share a ledger drops lines from the end,
        # pieces then questions, each list closed by `… N more: bin/ledger
        # show ADDRESS`; when the goal blocks and constraints alone exceed
        # it, the latest Goal block stays whole and the constraints become
        # their ids. A quote is never cut.
        class ResumeView
            BUDGET = 10_000
            SEPARATOR = "\n\n"

            # -> the view of FOUND (Found values), nil when there is none.
            def self.render(found, budget: BUDGET)
                return if found.empty?
                gaps = SEPARATOR.size * (found.size - 1)
                share = (budget - gaps) / found.size
                found.map { new(it).fit(share) }.join(SEPARATOR)
            end

            def initialize(found)
                @found = found
                @show = "bin/ledger show #{found.address}"
                markdown = Render::Markdown.new(found.snapshot)
                blocks = markdown.render.split("\n\n")
                @goals = blocks[1, found.snapshot.goals.size]
                @constraints = blocks.find { it.start_with?("Constraints") }
                @questions = questions(markdown)
                @pieces = pieces(markdown)
            end

            # The longest text within SHARE, dropping from the end.
            def fit(share)
                kept = [@questions.size, @pieces.size]
                text = compose(*kept)
                while text.size > share && kept.sum.positive?
                    kept[kept[1].positive? ? 1 : 0] -= 1
                    text = compose(*kept)
                end
                text.size > share ? fallback : text
            end

            private

            def head
                ["Ledger #{@found.address} — #{@show} for the whole",
                 @found.status_line].join("\n")
            end

            def compose(questions, pieces, goals: @goals,
                        constraints: @constraints)
                [head, *goals, constraints,
                 list("Open:", @questions, questions),
                 list("In flight:", @pieces, pieces)].compact.join(SEPARATOR)
            end

            def list(label, lines, kept)
                return if lines.empty?
                rest = lines.size - kept
                [label, *lines.first(kept),
                 (more(rest) if rest.positive?)].compact.join("\n")
            end

            def more(count) = "… #{count} more: #{@show}"

            # The latest Goal block whole, the earlier ones and the
            # constraints' text left to `show`.
            def fallback
                earlier = @goals.size - 1
                goals = [(if earlier.positive?
                              "… #{earlier} earlier Goal blocks: #{@show}"
                          end), *@goals.last(1)].compact
                compose(0, 0, goals:, constraints: constraint_ids)
            end

            def constraint_ids
                ids = @found.snapshot.constraints.map { "C#{it[:n]}" }
                return @constraints if ids.empty?
                "Constraints: #{ids.join(", ")}, in full: #{@show}"
            end

            def questions(markdown)
                @found.derive.open_questions.map do |question|
                    markdown.line("O#{question[:n]}")
                end
            end

            def pieces(markdown)
                derive = @found.derive
                derive.in_flight.map do |piece|
                    line = markdown.line("P#{piece[:n]}")
                    next "#{line} (ready)" if derive.ready?(piece)
                    derive.stalled?(piece) ? "#{line} (stalled)" : line
                end
            end
        end
    end
end
