# frozen_string_literal: true

require "ledger/hooks/ledgers"

module Ledger
    module Hooks
        # PreToolUse on TaskCreate and TodoWrite: while the session has a
        # live ledger its tasks live there, so a second list is denied. A
        # payload carrying `agent_id` comes from inside a subagent, whose
        # list is its own, and passes; a payload without one is the main
        # session's.
        module OneList
            TOOLS = %w[TaskCreate TodoWrite].freeze
            REASON = "this session keeps its tasks in the ledger: " \
                     "bin/ledger piece PATH new …"

            module_function

            def call(payload)
                return Answer.pass unless TOOLS.include?(payload["tool_name"])
                return Answer.pass unless payload["agent_id"].to_s.empty?
                return Answer.pass if live_ledgers(payload).empty?

                Answer.json(deny)
            end

            def live_ledgers(payload) = Ledgers.read(payload, derive: false)

            def deny
                { hookSpecificOutput: { hookEventName: "PreToolUse",
                                        permissionDecision: "deny",
                                        permissionDecisionReason: REASON } }
            end
        end
    end
end
