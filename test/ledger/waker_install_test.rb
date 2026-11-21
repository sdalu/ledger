# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "ledger/waker_install"

# rake waker:install and waker:uninstall on a settings file of the test's
# own: merged in without touching what is there, idempotent, the mode
# kept, a backup made, and taken out again exactly.
class WakerInstallTest < Minitest::Test
    W = Ledger::WakerInstall
    THEIRS = { "theme" => "dark",
               "hooks" => { "Stop" => [{ "hooks" => [
                   { "type" => "command", "command" => "echo done" }
               ] }] } }.freeze

    def setup
        @dir = Dir.mktmpdir("waker-install")
        @path = File.join(@dir, "settings.json")
        File.write(@path, JSON.generate(THEIRS))
        File.chmod(0o640, @path)
    end

    def teardown = FileUtils.rm_rf(@dir)

    def settings = JSON.parse(File.read(@path))

    def commands(event)
        settings.dig("hooks", event).flat_map { it["hooks"] }
                .map { it["command"] }
    end

    def test_install_merges_and_keeps_what_was_there
        assert_equal 3, W.install(@path).size
        assert_includes commands("Stop"), "echo done"
        assert_includes commands("Stop"), "#{W::GUARD} stamp"
        assert_includes commands("SessionStart"), "#{W::GUARD} session-start"
        assert_equal %w[dark accept],
                     settings.values_at("theme", "crossSessionInbound")
    end

    def test_install_keeps_the_mode_and_backs_the_file_up
        W.install(@path)

        assert_equal 0o640, File.stat(@path).mode & 0o777
        assert_path_exists "#{@path}.bak-waker"
    end

    def test_install_twice_changes_nothing
        W.install(@path)
        before = File.read(@path)

        assert_empty W.install(@path)
        assert_equal before, File.read(@path)
    end

    def test_a_session_start_wrapper_already_there_is_kept_alone
        wrapper = File.join(@dir, "ledger-hook.sh")
        File.write(wrapper, "#!/bin/sh\nexec ledger hook \"$1\"\n")
        File.write(@path, JSON.generate(
                              "hooks" => { "SessionStart" => [{ "hooks" => [
                                  { "type" => "command",
                                    "command" => "sh #{wrapper} session-start" }
                              ] }] }
                          ))
        W.install(@path)

        assert_equal ["sh #{wrapper} session-start"], commands("SessionStart")
    end

    def test_uninstall_takes_out_exactly_what_install_added
        W.install(@path)
        done = W.uninstall(@path)

        assert_equal 3, done.size
        assert_equal THEIRS, settings
    end
end
