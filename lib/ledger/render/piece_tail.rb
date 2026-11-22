# frozen_string_literal: true

require "ledger/render/refs"

module Ledger
    module Render
        # The fields that close a piece's line, after its evidence: `— no
        # commit: WHY`, `— commits: a1b2c3d, e4f5a6b`, `— picture: being
        # redrawn (WHY)` and `— picture: holds (WHY)`, then `—
        # dispatched: N× (last: …)` when a dispatch was announced (piece
        # --announce), `— gates: NAME STATE (DETAIL), …` and `— report:
        # STATUS`, the report's first line.
        class PieceTail
            def initialize(snapshot)
                @assessed = Refs.group(snapshot.piece_assessments, :piece_id)
                @commits = Refs.group(snapshot.piece_commits, :piece_id)
                @gates = Refs.group(snapshot.piece_gates, :piece_id)
                @reports = snapshot.piece_reports.to_h do |row|
                    [row[:piece_id], row[:status]]
                end
            end

            # [[name, value]] of the fields, the empty ones included.
            def call(piece)
                [["no commit", piece[:no_commit]], ["commits", commits(piece)],
                 ["picture", redrawn(piece)], ["picture", holds(piece)],
                 ["dispatched", dispatched(piece)], ["gates", gates(piece)],
                 ["report", @reports[piece[:id]]]]
            end

            private

            # "rubocop passed, unit failed (2 failures)": each gate's
            # state, in the order first recorded.
            def gates(piece)
                @gates.fetch(piece[:id], []).map do |row|
                    detail = " (#{row[:detail]})" if row[:detail]
                    "#{row[:name]} #{row[:state]}#{detail}"
                end.join(", ")
            end

            # "2\u00D7 (last: sonnet, medium, stakes low, risk 2/10)": the
            # dispatches announced and the last one's assessment, what it
            # left out left out.
            def dispatched(piece)
                rows = @assessed.fetch(piece[:id], [])
                last = rows.last or return

                "#{rows.size}\u00D7 (last: #{assessment(last)})"
            end

            def assessment(row)
                axis = row[:axis] && [row[:axis], row[:axis_level]].compact
                risk = row[:risk_rating]&.then { "risk #{it}/10" }
                parts = [row[:model], row[:effort], axis&.join(" "), risk]
                parts.compact.join(", ")
            end

            def commits(piece)
                rows = @commits.fetch(piece[:id], [])
                rows.sort_by { it[:position] }.map { it[:sha] }.join(", ")
            end

            def redrawn(piece)
                why = piece[:picture_pending] or return

                "being redrawn (#{why})"
            end

            def holds(piece)
                why = piece[:picture_holds] or return

                "holds (#{why})"
            end
        end
    end
end
