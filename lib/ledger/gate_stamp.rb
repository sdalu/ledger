# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"

require "ledger"

module Ledger
    # The stamp a passing gate leaves for the tree it tested: the tree
    # id of the git index (`git write-tree`), one per line in
    # <journal dir>/stamps/<repo id>, the last KEEP kept. The pre-commit
    # check (Githook) passes a commit whose staged tree is among them.
    #
    #     tree = Ledger::GateStamp.tree(repo)   # before the gate runs
    #     Ledger::GateStamp.write(repo, tree)   # when it passed
    #     Ledger::GateStamp.stamped?(repo, Ledger::GateStamp.tree(repo))
    module GateStamp
        KEEP = 50

        module_function

        # The tree id of REPO's index as it stands; nil when git cannot
        # write one (unmerged paths, not a repository).
        def tree(repo)
            out, _, status = Open3.capture3("git", "-C", repo, "write-tree")
            id = out.strip
            id if status.success? && id.match?(/\A\h{40,64}\z/)
        end

        # The repository's identity in the stamps directory: the digest
        # of its working tree's real path.
        def repo_id(repo)
            out, _, status = Open3.capture3("git", "-C", repo, "rev-parse",
                                            "--show-toplevel")
            raise Refused, "#{repo} is not a git working tree" unless
                status.success?

            Digest::SHA256.hexdigest(File.realpath(out.strip))[0, 16]
        end

        def file(repo)
            File.join(File.dirname(Journal.path), "stamps", repo_id(repo))
        end

        # The tree ids stamped for REPO, oldest first.
        def trees(repo)
            File.readlines(file(repo), chomp: true).reject(&:empty?)
        rescue Errno::ENOENT
            []
        end

        def stamped?(repo, tree) = !tree.nil? && trees(repo).include?(tree)

        # TREE appended to REPO's stamps, moved to the end when already
        # there, the oldest dropped beyond KEEP; the file replaced whole
        # so an interrupt leaves the old or the new one.
        def record(repo, tree)
            path = file(repo)
            kept = (trees(repo) - [tree] + [tree]).last(KEEP)
            FileUtils.mkdir_p(File.dirname(path))
            temp = "#{path}.#{Process.pid}.part"
            File.write(temp, "#{kept.join("\n")}\n")
            File.rename(temp, path)
        end

        # Stamp TESTED, the tree taken before the gate ran, when the
        # index still holds it; nothing written otherwise. The tree
        # written, nil when none.
        def write(repo, tested)
            return if tested.nil? || tree(repo) != tested

            record(repo, tested)
            tested
        end
    end
end
