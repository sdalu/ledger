# frozen_string_literal: true

require_relative "helper"

# viewer-guard: a command starting or stopping the viewer or the waker is
# denied with one sentence; restart and every other command pass.
class ViewerGuardTest < HookTest
    DENIED = ["ledger-viewer",
              "ledger-waker --once",
              "bin/ledger-viewer -p 4590",
              "/home/u/Repos/ledger/bin/ledger-waker",
              "rake server:start",
              "rake server:stop",
              "bundle exec rake server:start",
              "bundle exec rake server:stop",
              "bundle exec bin/ledger-viewer",
              "/opt/bin/low-priority bundle exec rake server:start",
              "/opt/bin/low-priority bin/ledger-waker",
              "nice -n 5 rake server:stop",
              "env LEDGER_JOURNAL=/x rake server:start",
              "env -i bin/ledger-viewer",
              "nohup bin/ledger-viewer &",
              "nohup bundle exec rake server:start > /dev/null 2>&1",
              "sh -c 'rake server:start'",
              "bash -c \"bundle exec rake server:stop\"",
              "sh -c 'nohup bin/ledger-waker'",
              "eval rake server:start",
              "echo go; rake server:stop",
              "cd /r && rake server:start",
              "echo $(rake server:start)",
              "if true; then rake server:start; fi"].freeze

    PASSES = ["rake server:restart",
              "bundle exec rake server:restart",
              "/opt/bin/low-priority bundle exec rake server:restart",
              "grep ledger-viewer README.md",
              "grep -n 'rake server:start' README.md",
              "echo ledger-waker",
              "echo \"rake server:stop\"",
              "cat bin/ledger-viewer",
              "ls -l bin/ledger-waker",
              "rake test",
              "rake -T",
              "bin/ledger check LEDGER.md",
              "git status"].freeze

    SENTENCE = "Refused: the user starts and stops the viewer; a session " \
               "only restarts it in place (rake server:restart)."

    def decision(command, tool: "Bash")
        answer = hook("viewer-guard", tool_name: tool,
                                      tool_input: { command: })
        answer.out && json(answer)["hookSpecificOutput"]
    end

    def test_starts_and_stops_are_denied_with_one_sentence
        DENIED.each do |command|
            out = decision(command)

            refute_nil out, command
            assert_equal "deny", out["permissionDecision"]
            assert_equal SENTENCE, out["permissionDecisionReason"]
        end
    end

    def test_restart_and_other_commands_pass
        PASSES.each { assert_nil decision(it), it }
    end

    def test_a_payload_that_is_not_bash_passes
        assert_nil decision("rake server:start", tool: "Edit")
    end
end
