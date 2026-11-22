# frozen_string_literal: true

require_relative "commit_repo"

# word-gate: in the main session, git commit and git merge in a project
# with a live ledger wait for the user's commit word on a piece.
class WordGateTest < HookTest
    include CommitRepo

    def gate(command, cwd: @repo, **extra)
        answer = hook("word-gate", cwd:, session_id: SESSION,
                                   tool_name: "Bash",
                                   tool_input: { command: }, **extra)
        answer.out && json(answer)["hookSpecificOutput"]
    end

    def refusal(command, **) = gate(command, **)["permissionDecisionReason"]

    def file(piece, shas)
        cli("piece", @address, piece, "--commits", shas.join(","))
    end

    def test_a_commit_without_a_word_is_refused_in_one_sentence
        piece("Land the sort", "commit")
        out = gate("git commit -m x")

        assert_equal "deny", out["permissionDecision"]
        assert_match(/\ARefused: git commit needs the user's commit word/,
                     out["permissionDecisionReason"])
        assert_equal 1, out["permissionDecisionReason"].scan(/\.\z/).size
    end

    def test_a_commit_with_an_unspent_word_passes
        piece("Land the sort", "commit")
        cli("word", @address, "P1", "--word", "commit")

        assert_nil gate("git commit -m x")
    end

    def test_a_word_whose_piece_holds_commits_is_spent
        piece("Land the sort", "commit")
        cli("word", @address, "P1", "--word", "commit")
        file("P1", [git_out("rev-parse", "--short=7", "HEAD").chomp])

        assert_match(/git commit needs/, refusal("git commit -m x"))
    end

    def test_launchers_and_shells_are_read_through
        piece("Land the sort", "commit")
        ["nice -n 5 git commit -m x", "timeout 9 git -C #{@repo} commit",
         "env A=1 git commit", "/opt/bin/low-priority git commit -m x",
         "sh -c 'git add a && git commit -m x'",
         "echo hi; git --no-pager commit"].each do |command|
            assert_match(/git commit needs/, refusal(command), command)
        end
    end

    def test_other_git_commands_pass
        piece("Land the sort", "commit")

        assert_nil gate("git status")
        assert_nil gate("git log --oneline")
        assert_nil gate("echo git commit")
        assert_nil gate("git commit-tree HEAD")
    end

    # Two pieces, the branch's first commit on P1, which has its word.
    def worded_branch
        piece("First", "commit")
        piece("Second", "commit")
        branch
        cli("word", @address, "P1", "--word", "commit")
        file("P1", landed.take(1))
    end

    def test_a_merge_of_commits_held_by_worded_pieces_passes
        worded_branch
        cli("word", @address, "P2", "--word", "commit")
        file("P2", landed.drop(1))

        assert_nil gate("git merge --ff-only feat")
    end

    def test_a_merge_names_the_commit_no_worded_piece_holds
        worded_branch
        file("P2", landed.drop(1))
        reason = refusal("git merge --ff-only feat")

        assert_includes reason, landed.last
        refute_includes reason, landed.first
        assert_match(/git merge needs/, reason)
    end

    def test_a_merge_with_nothing_to_land_passes
        piece("First", "commit")

        assert_nil gate("git merge --ff-only #{@base}")
    end

    def test_a_push_is_not_gated
        piece("First", "commit")

        assert_nil gate("git push origin main")
    end

    def test_no_live_ledger_passes_silently
        piece("First", "commit")
        other = File.realpath(Dir.mktmpdir("no-ledger", @dir))

        assert_nil gate("git commit -m x", cwd: other)
    end

    def test_a_delegate_passes
        piece("First", "commit")

        assert_nil gate("git commit -m x", agent_id: "a1", agent_type: "x")
        assert_match(/git commit needs/, refusal("git commit", agent_id: ""))
    end
end
