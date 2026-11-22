# frozen_string_literal: true

require "fileutils"
require "shellwords"

require "ledger/gate_stamp"
require "ledger/git_repo"

module Ledger
    # The git pre-commit hook that checks a commit's staged tree against
    # the gate's stamps (GateStamp): a commit made from a Claude session
    # (CLAUDECODE set) is refused without a stamp, any other gets a
    # one-line warning and goes through. `install` puts the hook in a
    # hooks directory of its own under .git, or in the directory
    # core.hooksPath already names, chaining the pre-commit hook it
    # finds there; `uninstall` puts the previous state back.
    module Githook
        MARK = "# ledger githook: managed, `ledger githook uninstall` removes"
        OWN_DIR = "ledger-hooks"
        PREVIOUS = "pre-commit.ledger-previous"
        LEDGER = File.expand_path("../../bin/ledger", __dir__)

        extend GitRepo

        module_function

        # The pre-commit check for REPO: 0 passes, 1 refuses. Says why
        # on ERR.
        def check(repo, env: ENV, err: $stderr)
            return 0 if GateStamp.stamped?(repo, GateStamp.tree(repo))
            return warn_only(err) if env.fetch("CLAUDECODE", "").empty?

            err.puts "ledger: commit refused: no passing gate stamp " \
                     "matches the staged tree; run the gate (rake) " \
                     "and commit again"
            1
        end

        def warn_only(err)
            err.puts "ledger: warning: no passing gate stamp matches " \
                     "this tree (run the gate: rake)"
            0
        end

        # What `install` did, one line.
        def install(repo)
            return already(repo) if ours?(repo)

            local = hooks_path(repo)
            return install_in(repo, local) if local

            install_own(repo)
        end

        def uninstall(repo)
            local = hooks_path(repo)
            if local && own_dir?(repo, local)
                git(repo, "config", "--local", "--unset", "core.hooksPath")
                FileUtils.rm_rf(local)
                "uninstalled: #{local} removed, core.hooksPath unset"
            elsif local && marked?(File.join(local, "pre-commit"))
                uninstall_in(local)
            else
                "not installed: nothing to remove"
            end
        end

        # --- the directory core.hooksPath already names

        def install_in(repo, dir)
            hook = File.join(dir, "pre-commit")
            previous = File.join(dir, PREVIOUS)
            if File.exist?(hook)
                refuse_taken(previous)
                File.rename(hook, previous)
            end
            write_hook(hook, (previous if File.exist?(previous)))
            "installed in #{dir} (core.hooksPath of #{repo})"
        end

        def refuse_taken(previous)
            return unless File.exist?(previous)

            raise Refused, "#{previous} exists already; not overwritten"
        end

        def uninstall_in(dir)
            hook = File.join(dir, "pre-commit")
            previous = File.join(dir, PREVIOUS)
            File.delete(hook)
            File.rename(previous, hook) if File.exist?(previous)
            "uninstalled: #{hook} restored"
        end

        # --- a directory of its own under .git

        def install_own(repo)
            hooks = File.join(common_dir(repo), "hooks")
            dir = own_path(repo)
            FileUtils.mkdir_p(dir)
            link_others(hooks, dir)
            previous = File.join(hooks, "pre-commit")
            write_hook(File.join(dir, "pre-commit"),
                       (previous if File.file?(previous)))
            git(repo, "config", "--local", "core.hooksPath", dir)
            "installed in #{dir}, core.hooksPath set"
        end

        # The repository's other hooks, linked so that pointing
        # core.hooksPath at DIR does not switch them off.
        def link_others(hooks, dir)
            Dir.glob(File.join(hooks, "*")).each do |path|
                name = File.basename(path)
                next if name == "pre-commit" || name.end_with?(".sample")

                FileUtils.ln_sf(path, File.join(dir, name))
            end
        end

        # --- the hook file

        # A pre-commit script running the check, then PREVIOUS if any.
        def write_hook(path, previous)
            lines = ["#!/bin/sh", MARK,
                     "#{Shellwords.escape(LEDGER)} githook check || exit 1"]
            lines << "exec #{Shellwords.escape(previous)} \"$@\"" if previous
            temp = "#{path}.#{Process.pid}.part"
            File.write(temp, "#{lines.join("\n")}\nexit 0\n")
            File.chmod(0o755, temp)
            File.rename(temp, path)
        end

        def marked?(path) = File.file?(path) && File.read(path).include?(MARK)

        def ours?(repo)
            local = hooks_path(repo)
            return false unless local

            own_dir?(repo, local) || marked?(File.join(local, "pre-commit"))
        end

        def already(repo)
            "already installed (core.hooksPath #{hooks_path(repo)})"
        end

        def own_path(repo) = File.join(common_dir(repo), OWN_DIR)

        def own_dir?(repo, dir)
            File.realpath(dir) == File.realpath(own_path(repo))
        rescue Errno::ENOENT
            false
        end
    end
end
