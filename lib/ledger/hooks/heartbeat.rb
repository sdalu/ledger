# frozen_string_literal: true

module Ledger
    module Hooks
        # PostToolUse on Bash: when the command ran `ledger … check` or
        # `ledger … status`, the last `Status —` line it printed goes to
        # the user as a systemMessage. The user does not see tool output,
        # so a check that ran is no heartbeat until this shows it. Nothing
        # is denied or rewritten; the standard library alone, since it
        # runs after every Bash call.
        module Heartbeat
            # `ledger` as a command word (bin/ledger, ./ledger), not
            # ledger-viewer, then check or status later on
            # the line.
            LEDGER = %r{(?:^|[\s/])ledger\s.*\b(?:check|status)\b}
            STATUS = /^Status — .+$/
            KEYS = %w[stdout output content].freeze

            module_function

            def call(payload)
                return Answer.pass unless payload["tool_name"] == "Bash"
                return Answer.pass unless LEDGER.match?(command(payload))

                line = output(payload["tool_response"]).scan(STATUS).last
                line ? Answer.json(systemMessage: line) : Answer.pass
            end

            def command(payload)
                input = payload["tool_input"]
                input.is_a?(Hash) ? input["command"].to_s : ""
            end

            # The tool's printed output, whatever shape the response takes.
            def output(response)
                case response
                when String then response
                when Hash then KEYS.map { response[it].to_s }.join("\n")
                when Array then response.map { output(it) }.join("\n")
                else ""
                end
            end
        end
    end
end
