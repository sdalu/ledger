# frozen_string_literal: true

require_relative "../support/hook_repo"

# The pre-commit hook: what it passes and refuses, and install and
# uninstall chaining and restoring what the repository had.
class GithookTest < HookRepoCase
    def test_a_claude_commit_is_refused_without_a_stamp
        install
        status, out = commit(claude: "1")

        refute_predicate status, :success?
        assert_includes out, "commit refused"
        refute_predicate git("rev-parse", "--verify", "-q", "HEAD").last,
                         :success?
    end

    def test_a_claude_commit_goes_through_with_a_stamp
        install
        Ledger::GateStamp.write(@repo, tree)

        assert_predicate commit(claude: "1").first, :success?
    end

    def test_a_stamp_does_not_cover_another_tree
        install
        Ledger::GateStamp.write(@repo, tree)
        stage("b.txt", "more\n")

        refute_predicate commit(claude: "1").first, :success?
    end

    def test_a_hand_made_commit_is_warned_and_goes_through
        install
        status, out = commit(claude: nil)

        assert_predicate status, :success?
        assert_includes out, "warning: no passing gate stamp"
        assert_equal 1, git("log", "--oneline").first.lines.size
    end

    def test_install_chains_an_existing_hook_and_uninstall_restores_it
        old = File.join(hooks_dir, "pre-commit")
        hook_file(old, "echo OLD-HOOK-RAN >&2")
        before = File.read(old)
        install
        out = commit(claude: nil).last

        assert_includes out, "OLD-HOOK-RAN"
        assert_includes out, "warning"
        uninstall

        assert_equal before, File.read(old)
        assert_restored
    end

    def test_a_failing_chained_hook_still_blocks
        hook_file(File.join(hooks_dir, "pre-commit"), "exit 1")
        install

        refute_predicate commit(claude: nil).first, :success?
    end

    def test_install_and_uninstall_are_idempotent
        _, first = run_cli("githook", "install", @repo)
        _, second = run_cli("githook", "install", @repo)

        assert_includes first, "installed in"
        assert_includes second, "already installed"
        uninstall
        _, again = run_cli("githook", "uninstall", @repo)

        assert_includes again, "not installed"
    end

    def test_other_hooks_keep_running_after_install
        hook_file(File.join(hooks_dir, "post-commit"), "echo POST-RAN >&2")
        install

        assert_includes commit(claude: nil).last, "POST-RAN"
    end

    def test_a_hooks_path_already_set_is_used_and_restored
        old = custom_hook
        before = File.read(old)
        install
        out = commit(claude: nil).last
        uninstall

        assert_includes out, "CUSTOM-RAN"
        assert_equal before, File.read(old)
        assert_equal ["pre-commit"], Dir.children(File.dirname(old))
        assert_equal "myhooks\n", git("config", "core.hooksPath").first
    end

    def test_a_hooks_path_set_outside_the_repository_is_not_touched
        outer = { "GIT_CONFIG_COUNT" => "1",
                  "GIT_CONFIG_KEY_0" => "core.hooksPath",
                  "GIT_CONFIG_VALUE_0" => File.join(@dir, "shared") }
        saved = outer.to_h { |key, _| [key, ENV.fetch(key, nil)] }
        outer.each { |key, value| ENV[key] = value }
        code, _, err = run_cli("githook", "install", @repo)

        assert_equal 2, code
        assert_includes err, "set outside the repository"
    ensure
        saved&.each { |key, value| ENV[key] = value }
    end

    private

    # A pre-commit hook in myhooks, which core.hooksPath now names.
    def custom_hook
        dir = File.join(@repo, "myhooks")
        FileUtils.mkdir_p(dir)
        hook_file(File.join(dir, "pre-commit"), "echo CUSTOM-RAN >&2")
        git("config", "core.hooksPath", "myhooks")
        File.join(dir, "pre-commit")
    end

    def install = assert_equal(0, run_cli("githook", "install", @repo).first)

    def uninstall
        assert_equal(0, run_cli("githook", "uninstall", @repo).first)
    end

    # No core.hooksPath of the repository's own, no directory of ours.
    def assert_restored
        assert_empty git("config", "--local", "--get-all",
                         "core.hooksPath").first
        refute Dir.exist?(File.join(@repo, ".git", "ledger-hooks"))
    end
end
