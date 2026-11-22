# frozen_string_literal: true

require_relative "commit_repo"

# commit-record: no piece meant, the commits are named to the session;
# no move, no first sight, no git and no ledger are silent.
class CommitRecordQuietTest < HookTest
    include CommitRepo

    def test_no_matching_piece_names_the_commits
        piece("Wait for deploy", "deploy")
        branch
        seen
        answer = merge

        assert_empty held(1)
        assert_includes context(answer),
                        "`bin/ledger piece #{@address} P<n> --commits " \
                        "#{landed.join(",")}`"
    end

    def test_a_head_that_did_not_move_is_silent
        piece("Land the sort", "commit")
        branch
        assert_equal Ledger::Hooks::Answer.pass, seen
        assert_equal Ledger::Hooks::Answer.pass, run_hook("git log")
        assert_empty held(1)
    end

    def test_the_first_sight_only_remembers
        piece("Land the sort", "commit")
        branch
        assert_equal Ledger::Hooks::Answer.pass, merge
        assert_empty held(1)
    end

    def test_a_command_without_git_is_not_a_sight
        piece("Land the sort", "commit")
        branch
        run_hook("ls")
        git("merge", "-q", "--ff-only", "feat")

        assert_equal Ledger::Hooks::Answer.pass, run_hook("git log")
    end

    def test_a_repository_without_a_ledger_is_silent
        branch
        seen
        db[:ledgers].where(place: @repo).update(closed_at: 1)

        assert_equal Ledger::Hooks::Answer.pass, merge
    end
end
