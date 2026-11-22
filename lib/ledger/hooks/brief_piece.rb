# frozen_string_literal: true

require "ledger/hooks/ledgers"

module Ledger
    module Hooks
        # PreToolUse on Agent: with a live ledger in the session's place,
        # a dispatch whose prompt carries no header line `Piece: PATH
        # P<n>` between its BRIEF line and the first blank line after it
        # is denied, as is one naming a piece that is not planned and
        # ready. `Piece: none — WHY` lets a delegate that is no piece
        # through. With no live ledger the dispatch passes; the piece is
        # never set out here (the orchestrator does that).
        module BriefPiece
            TOOLS = %w[Agent Task].freeze
            HEADER = /\APiece:[[:space:]]*(.*?)[[:space:]]*\z/
            NAMED = /\A(\S+)[[:space:]]+(P[1-9][0-9]*)\z/
            NONE = /\Anone[[:space:]]*—[[:space:]]*\S/
            ADD = "add the header line `Piece: <absolute .md path of the " \
                  "ledger> P<n>` (a planned, ready piece) under the BRIEF " \
                  "line, or `Piece: none — WHY` for a delegate that is no " \
                  "piece"

            module_function

            def call(payload)
                return Answer.pass unless TOOLS.include?(payload["tool_name"])

                input = payload["tool_input"]
                prompt = input.is_a?(Hash) ? input["prompt"].to_s : ""
                found = Ledgers.read(payload)
                return Answer.pass if found.empty?

                problem = problem(header(prompt), found)
                problem ? Answer.json(deny(problem)) : Answer.pass
            end

            # The value of the first Piece: line of the header block, nil
            # when there is none.
            def header(prompt)
                lines = prompt.lines(chomp: true).map(&:strip)
                start = lines.index { it.match?(/\ABRIEF\b/) }
                return unless start

                block = lines.drop(start + 1).take_while { !it.empty? }
                block.filter_map { HEADER.match(it)&.captures&.first }.first
            end

            # What is wrong with the header VALUE, nil when the dispatch
            # may go.
            def problem(value, found)
                return "has no Piece: header line" if value.nil?
                return if NONE.match?(value)

                named = NAMED.match(value)
                return "has the header `Piece: #{value}`" unless named

                path, ref = named.captures
                bad = bad_path(path)
                return "names the path #{path.inspect}, #{bad}" if bad

                unready(found, path, ref)
            end

            def bad_path(path)
                return "not absolute" unless path.start_with?("/")

                "not a .md file" unless path.end_with?(".md")
            end

            def unready(found, path, ref)
                ledger = found.find { it.address == path }
                return "names #{path}, which is no live ledger here" unless
                    ledger

                piece = ledger.derive.pieces.find { "P#{it[:n]}" == ref }
                return "names #{ref}, which #{path} does not have" unless piece
                return if ledger.derive.ready?(piece)

                "names #{ref}, which is #{piece[:status]} and not ready " \
                    "(planned, awaiting no word, its after pieces ended)"
            end

            def deny(problem)
                { hookSpecificOutput: { hookEventName: "PreToolUse",
                                        permissionDecision: "deny",
                                        permissionDecisionReason:
                                            "Dispatch refused: the brief " \
                                            "#{problem}; #{ADD}." } }
            end
        end
    end
end
