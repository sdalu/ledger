# frozen_string_literal: true

require "ledger/hooks/dispatch_writers"
require "ledger/hooks/ledgers"

module Ledger
    module Hooks
        # PreToolUse on Agent: with a live ledger in the session's place,
        # a dispatch whose prompt carries no header line `Piece: PATH
        # P<n>` between its BRIEF line and the first blank line after it
        # is denied, as is one naming a piece that is neither ready nor
        # out under the dispatching session (claimed by its session_id).
        # `Piece: none — WHY` lets a delegate that is no piece through.
        # A dispatch that writes (see DispatchWriters) without isolation
        # worktree is denied while another piece of the session is out
        # with a writing dispatch; readers always pass.
        # With no live ledger the dispatch passes; the piece is never set
        # out here (the orchestrator does that).
        module BriefPiece
            TOOLS = %w[Agent Task].freeze
            HEADER = /\APiece:[[:space:]]*(.*?)[[:space:]]*\z/
            NAMED = /\A(\S+)[[:space:]]+(P[1-9][0-9]*)\z/
            NONE = /\Anone[[:space:]]*—[[:space:]]*\S/
            ADD = "add the header line `Piece: <absolute .md path of the " \
                  "ledger> P<n>` (a ready piece, or one out under this " \
                  "session) under the BRIEF line, or `Piece: none — WHY` " \
                  "for a delegate that is no piece"

            module_function

            def call(payload)
                return Answer.pass unless TOOLS.include?(payload["tool_name"])

                input = payload["tool_input"]
                prompt = input.is_a?(Hash) ? input["prompt"].to_s : ""
                found = Ledgers.read(payload)
                return Answer.pass if found.empty?

                reason = reason(payload, input, prompt, found)
                reason ? Answer.json(deny(reason)) : Answer.pass
            end

            # Why the dispatch may not go, nil when it may.
            def reason(payload, input, prompt, found)
                value = header(prompt)
                session = payload["session_id"]
                problem = problem(value, found, session)
                return brief(problem) if problem

                clash = DispatchWriters.admit(input, prompt, found, session,
                                              NAMED.match(value)&.captures)
                "Dispatch refused: it #{clash}." if clash
            end

            # The value of the first Piece: line of the header block, nil
            # when there is none.
            def header(prompt)
                block = DispatchWriters.block(prompt)
                block.filter_map { HEADER.match(it)&.captures&.first }.first
            end

            # What is wrong with the header VALUE, nil when the dispatch
            # may go.
            def problem(value, found, session)
                return "has no Piece: header line" if value.nil?
                return if NONE.match?(value)

                named = NAMED.match(value)
                return "has the header `Piece: #{value}`" unless named

                path, ref = named.captures
                bad = bad_path(path)
                return "names the path #{path.inspect}, #{bad}" if bad

                unready(found, path, ref, session)
            end

            def bad_path(path)
                return "not absolute" unless path.start_with?("/")

                "not a .md file" unless path.end_with?(".md")
            end

            def unready(found, path, ref, session)
                ledger = found.find { it.address == path }
                return "names #{path}, which is no live ledger here" unless
                    ledger

                piece = ledger.derive.pieces.find { "P#{it[:n]}" == ref }
                return "names #{ref}, which #{path} does not have" unless piece
                return if sendable?(ledger.derive, piece, session)

                "names #{ref}, which is #{piece[:status]}, neither ready " \
                    "nor out under this session"
            end

            # A piece ready to send, or out and claimed by this session
            # (the orchestrator marks it out before dispatching it).
            def sendable?(derive, piece, session)
                return derive.ready?(piece) unless piece[:status] == "out"

                !session.to_s.empty? && piece[:claimed_by] == session
            end

            def brief(problem)
                "Dispatch refused: the brief #{problem}; #{ADD}."
            end

            def deny(reason)
                { hookSpecificOutput: { hookEventName: "PreToolUse",
                                        permissionDecision: "deny",
                                        permissionDecisionReason: reason } }
            end
        end
    end
end
