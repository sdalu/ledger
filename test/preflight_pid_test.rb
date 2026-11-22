# frozen_string_literal: true

require_relative "test_helper"
require "rake"
require "tmpdir"

# Preflight.running_pid: a pidfile's number counts only when it is a live
# puma of this checkout's directory.
class PreflightPidTest < Minitest::Test
    ROOT = File.expand_path("..", __dir__)

    def setup
        load File.join(ROOT, "rakelib/preflight.rake") unless
            defined?(Preflight)
        @dir = File.realpath(Dir.mktmpdir("pid"))
        @pids = []
        @was = Dir.pwd
        Dir.chdir(@dir)
        FileUtils.mkdir_p("tmp")
    end

    def teardown
        Dir.chdir(@was)
        @pids.each do |pid|
            Process.kill("TERM", pid)
            Process.wait(pid)
        end
        FileUtils.rm_rf(@dir)
    end

    # A process whose command line starts with TITLE, named by the pidfile.
    def titled(title)
        pid = Process.spawn(%W[sleep #{title}], "60")
        @pids << pid
        sleep 0.2
        File.write(Preflight::PIDFILE, "#{pid}\n")
        pid
    end

    def test_a_live_puma_of_this_directory_is_ours
        pid = titled("puma 8.0.2 (tcp://127.0.0.1:1) [#{File.basename(@dir)}]")

        assert_equal pid, Preflight.running_pid
    end

    def test_a_live_process_that_is_no_puma_is_not
        titled("sleeper 1.0")

        assert_nil Preflight.running_pid
    end

    def test_a_puma_of_another_directory_is_not
        titled("puma 8.0.2 (tcp://127.0.0.1:1) [elsewhere]")

        assert_nil Preflight.running_pid
    end

    def test_a_pid_of_another_user_is_not_ours
        File.write(Preflight::PIDFILE, "1\n")

        assert_nil Preflight.running_pid
    end

    def test_a_dead_pid_is_not
        pid = Process.spawn("true")
        Process.wait(pid)
        File.write(Preflight::PIDFILE, "#{pid}\n")

        assert_nil Preflight.running_pid
    end
end
