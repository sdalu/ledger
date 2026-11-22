# frozen_string_literal: true

require_relative "helper"

# one-list: a task list beside a live ledger is denied in the main
# session and left alone inside a subagent.
class OneListTest < HookTest
    def call(tool, cwd: PLACE, **)
        answer = hook("one-list", tool_name: tool, cwd:, tool_input: {}, **)
        answer.out && json(answer)["hookSpecificOutput"]
    end

    def test_both_tools_are_denied_with_the_ledger_command
        %w[TaskCreate TodoWrite].each do |tool|
            out = call(tool)

            assert_equal "deny", out["permissionDecision"]
            assert_match "bin/ledger piece PATH new",
                         out["permissionDecisionReason"]
        end
    end

    def test_a_call_from_inside_a_subagent_passes
        assert_nil call("TaskCreate", agent_id: "a1b2")
    end

    def test_no_live_ledger_and_other_tools_pass_silently
        assert_nil call("TaskCreate", cwd: "/work/beta")
        assert_nil call("Bash")
    end
end
