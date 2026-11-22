# frozen_string_literal: true

require "open3"

require "ledger"

module Ledger
    # What the hook installer asks of a repository: where its working
    # tree and shared git directory are, and the core.hooksPath its own
    # config sets. Extended by the module that needs them.
    module GitRepo
        # core.hooksPath as the repository's own config sets it, made
        # absolute against the working tree; nil when unset. A path set
        # in another scope is refused, since a hook written there would
        # act on every repository using it.
        def hooks_path(repo)
            value = git(repo, "config", "--local", "--get", "core.hooksPath",
                        ok: [0, 1])
            return File.expand_path(value, toplevel(repo)) unless value.empty?

            refuse_outer(repo)
            nil
        end

        def refuse_outer(repo)
            outer = git(repo, "config", "--get", "core.hooksPath", ok: [0, 1])
            return if outer.empty?

            raise Refused, "core.hooksPath is set outside the repository " \
                           "(#{outer}); not touched"
        end

        def toplevel(repo) = git(repo, "rev-parse", "--show-toplevel")

        # The git directory the worktrees of REPO share.
        def common_dir(repo)
            File.expand_path(git(repo, "rev-parse", "--git-common-dir"),
                             toplevel(repo))
        end

        # The output of git run in REPO, stripped; refused when its exit
        # status is not among OK.
        def git(repo, *, ok: [0])
            out, err, status = Open3.capture3("git", "-C", repo, *)
            return out.strip if ok.include?(status.exitstatus)

            raise Refused, "git #{err.strip}"
        end
    end
end
