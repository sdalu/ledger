# frozen_string_literal: true

require_relative "helper"

# The heartbeat: the last status line a `ledger check|status` printed
# goes to the user; any other command is silent.
class HeartbeatTest < HookTest
    STATUS = "Status (Build it) — criteria 0/1 · pieces 0/0 verified"

    def beat(command, response)
        hook("heartbeat", tool_name: "Bash",
                          tool_input: { command: }, tool_response: response)
    end

    def test_the_last_status_line_of_a_check_is_shown
        answer = beat("bin/ledger check /w/LEDGER.md",
                      { stdout: "Status (Old) — x\nok x\n#{STATUS}\n" })

        assert_equal({ "systemMessage" => STATUS }, json(answer))
    end

    def test_status_and_a_response_as_text_or_list_are_read
        answer = beat("ledger status /w/LEDGER.md", [STATUS])

        assert_equal STATUS, json(answer)["systemMessage"]
    end

    def test_other_commands_and_no_status_line_are_silent
        [["bin/ledger-viewer status", { stdout: STATUS }],
         ["bin/ledger show /w/LEDGER.md", { stdout: STATUS }],
         ["bin/ledger check /w/LEDGER.md", { stdout: "ok x" }]]
            .each do |command, response|
            assert_nil beat(command, response).out, command
        end
    end

    def test_another_tool_is_silent
        assert_nil hook("heartbeat", tool_name: "Read").out
    end
end
