# frozen_string_literal: true

require_relative "helper"

# edit-record: the path an edit tool names is appended to the session's
# record beside the throwaway journal, once.
class EditRecordTest < HookTest
    SESSION = "s-1234"
    FILE = "/work/alpha/a.txt"

    def record = File.join(@dir, "state", "edits", SESSION)

    def edit(path, tool: "Edit", key: "file_path", session: SESSION)
        hook("edit-record", session_id: session, tool_name: tool,
                            tool_input: { key => path })
    end

    def test_record_appends_and_deduplicates
        other = "/work/alpha/b.txt"
        edit(FILE)
        edit(FILE)
        edit(other, tool: "NotebookEdit", key: "notebook_path")

        assert_equal [FILE, other], File.readlines(record, chomp: true)
        assert_equal Ledger::Hooks::Answer.pass, edit(FILE)
    end

    def test_record_ignores_a_payload_without_session_or_path
        assert_equal Ledger::Hooks::Answer.pass, edit(FILE, session: "../x")
        assert_equal Ledger::Hooks::Answer.pass,
                     hook("edit-record", session_id: SESSION, tool_input: {})
        refute_path_exists record
    end

    def test_the_launcher_runs_edit_record_without_bundler
        _, _, status = launch("edit-record",
                              { session_id: SESSION, tool_name: "Write",
                                tool_input: { file_path: FILE } },
                              "BUNDLE_GEMFILE" => "/nonexistent/Gemfile")

        assert_equal 0, status.exitstatus
        assert_equal [FILE], File.readlines(record, chomp: true)
    end
end
