# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "stringio"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ledger/cli"

# A scratch git repository with one staged file and a journal path of
# its own, for the gate stamp and the pre-commit hook; nothing here
# installs a hook anywhere else.
class HookRepoCase < Minitest::Test
    def setup
        @dir = Dir.mktmpdir("hook-repo")
        @repo = File.join(@dir, "repo")
        @journal = File.join(@dir, "state", "journal.db")
        @saved = ENV.fetch("LEDGER_JOURNAL", nil)
        ENV["LEDGER_JOURNAL"] = @journal
        FileUtils.mkdir_p(@repo)
        git("init", "-q")
        git("config", "user.name", "t")
        git("config", "user.email", "t@example.invalid")
        stage("a.txt", "one\n")
    end

    def teardown
        ENV["LEDGER_JOURNAL"] = @saved
        FileUtils.rm_rf(@dir)
    end

    private

    def stamp_file = Ledger::GateStamp.file(@repo)
    def tree = Ledger::GateStamp.tree(@repo)

    # -> [exit status, stdout, stderr] of one ledger command.
    def run_cli(*argv)
        out = StringIO.new
        err = StringIO.new
        code = Ledger::CLI.run(argv, out:, err:)
        [code, out.string, err.string]
    end

    def stage(name, text)
        File.write(File.join(@repo, name), text)
        git("add", name)
    end

    # [output, status] of git in the scratch repository, stderr joined.
    def git(*) = Open3.capture2e("git", "-C", @repo, *)

    # An executable hook file at PATH running BODY.
    def hook_file(path, body)
        File.write(path, "#!/bin/sh\n#{body}\n")
        File.chmod(0o755, path)
    end

    def hooks_dir = File.join(@repo, ".git", "hooks")

    # A commit as a Claude session makes it (CLAUDECODE set) or by hand
    # (unset); [status, output].
    def commit(claude:)
        env = { "LEDGER_JOURNAL" => @journal, "CLAUDECODE" => claude }
        out, status = Open3.capture2e(env, "git", "-C", @repo, "commit",
                                      "-q", "-m", "x")
        [status, out]
    end
end
