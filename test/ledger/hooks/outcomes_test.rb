# frozen_string_literal: true

require_relative "helper"

# The hooks' outcomes: a PreToolUse deny is a refusal under the hook's
# name, in-process and on the fast path (the sqlite3 program); a Stop
# hook's verdict is a hook row, sent-back or let-through and why; a
# failing recorder changes no answer.
class HookOutcomesTest < HookTest
    VIEWER = { tool_name: "Bash",
               tool_input: { command: "ledger-viewer start" } }.freeze

    def outcomes = db[:outcomes].order(:id).all
    def columns(*names) = outcomes.map { it.values_at(*names) }

    # A finished ledger: one piece verified, its criterion unmarked.
    def finished
        write("import") do |change|
            goal(change)
            criterion(change)
            piece(change, status: "verified", evidence: "ran it")
        end
    end

    def test_a_deny_is_a_refusal_under_the_hook_name
        answer = hook("viewer-guard", **VIEWER)

        assert_equal "deny",
                     json(answer)["hookSpecificOutput"]["permissionDecision"]
        assert_equal 1, outcomes.size
        row = outcomes.first
        assert_equal ["refusal", "viewer-guard", @ledger[:id]],
                     row.values_at(:kind, :rule, :ledger_id)
        assert_includes row[:detail], "the user starts and stops the viewer"
    end

    def test_a_pass_records_nothing
        hook("viewer-guard", tool_name: "Bash",
                             tool_input: { command: "ls" })

        assert_empty outcomes
    end

    def test_a_fast_path_deny_is_written_through_the_sqlite3_program
        out, _err, status = launch("viewer-guard", { cwd: PLACE, **VIEWER })

        assert status.success?
        assert_includes out, "\"permissionDecision\":\"deny\""
        assert_equal [%w[refusal viewer-guard]], columns(:kind, :rule)
    end

    def test_a_failing_recorder_leaves_the_deny_as_it_was
        db.drop_table(:outcomes)
        _out, err, = launch("viewer-guard", { cwd: PLACE, **VIEWER })
        answer = hook("viewer-guard", **VIEWER)

        assert_equal "deny",
                     json(answer)["hookSpecificOutput"]["permissionDecision"]
        assert_empty err
    end

    def test_finish_sending_back_records_the_rules_failed
        finished
        hook("finish")
        hook("finish", stop_hook_active: true)

        details = columns(:kind, :rule, :detail)
        assert_equal %w[hook finish], details.first.first(2)
        assert_match(/\Asent-back: final fails: .*final-criteria/,
                     details.first.last)
        assert_equal ["hook", "finish", "let-through: retry"], details.last
    end

    def test_finish_letting_through_says_why
        write("import") do |change|
            goal(change)
            criterion(change)
            piece(change)
        end
        hook("finish")

        assert_equal [["let-through: work not over"]], columns(:detail)
    end

    def test_status_stop_records_its_verdict
        write("import") { piece(it) }
        hook("status-stop", session_id: "s1")

        assert_equal [["status-stop", "let-through: nothing in flight"]],
                     columns(:rule, :detail)
    end

    def test_a_stop_away_from_any_ledger_records_nothing
        Ledger::Hooks.answer("finish",
                             JSON.generate({ cwd: "/elsewhere" }))

        assert_empty outcomes
    end
end
