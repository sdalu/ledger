# frozen_string_literal: true

require_relative "helper"

# The dispatcher and the launcher: unknown words, bad payloads, a
# journal that is not there, and the bare start of the two journal-free
# hooks.
class MainTest < HookTest
    def test_an_unknown_hook_exits_one
        err = StringIO.new
        status = Ledger::Hooks.main(["nope"], input: StringIO.new("{}"),
                                              out: StringIO.new, err:)

        assert_equal 1, status
        assert_match "no hook \"nope\"", err.string
    end

    def test_a_bad_payload_and_an_own_error_pass
        assert_equal Ledger::Hooks::Answer.pass,
                     Ledger::Hooks.answer("finish", "not json")
        assert_equal Ledger::Hooks::Answer.pass,
                     Ledger::Hooks.answer("finish", "[1]")
        assert_equal Ledger::Hooks::Answer.pass,
                     hook("brief-constraints", tool_name: "Agent",
                                               tool_input: "a string")
    end

    def test_no_journal_file_passes_and_creates_none
        missing = File.join(@dir, "none", "journal.db")
        ENV["LEDGER_JOURNAL"] = missing

        assert_equal Ledger::Hooks::Answer.pass,
                     hook("session-start", source: "startup")
        refute_path_exists missing
    end

    def test_the_launcher_runs_the_journal_free_hooks_without_bundler
        out, _, status = launch("heartbeat",
                                { tool_name: "Bash",
                                  tool_input: { command: "ledger status" },
                                  tool_response: "Status (T) — x" },
                                "BUNDLE_GEMFILE" => "/nonexistent/Gemfile")

        assert_equal 0, status.exitstatus
        assert_equal "{\"systemMessage\":\"Status (T) — x\"}\n", out
    end

    def test_the_launcher_runs_a_journal_hook_under_the_bundle
        write("import") { entry(it, text: "hello") }
        _, err, status = launch("inbox", { cwd: PLACE })

        assert_equal 2, status.exitstatus
        assert_match "N1 (2026-11-20 10:00:00, note):\n    hello", err
    end
end
