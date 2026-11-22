# frozen_string_literal: true

require_relative "commit_repo"

# commit-record: a HEAD that moved in a repository, seen by a Bash
# command naming git, puts the commits on the piece whose commit word
# the session filed, else on the one piece awaiting commit.
class CommitRecordTest < HookTest
    include CommitRepo

    def test_a_fast_forward_of_two_commits_goes_on_the_piece_given_its_word
        piece("Wait for deploy", "deploy")
        piece("Land the sort", "commit")
        cli("word", @address, "P2", "--word", "commit")
        branch
        seen
        answer = merge

        assert_equal landed, held(2)
        assert_equal 2, landed.size
        assert_empty held(1)
        assert_includes context(answer), "recorded on P2"
    end

    def test_a_piece_awaiting_commit_alone_takes_them_without_a_word
        piece("Land the sort", "commit")
        branch
        seen
        merge

        assert_equal landed, held(1)
    end

    def test_a_word_of_another_session_does_not_pick_the_piece
        piece("Land the sort", "commit")
        piece("Land the other", "commit")
        word_by("s-other", "P1")
        branch
        seen
        answer = merge

        assert_empty held(1)
        assert_equal landed, held(2)
        assert_includes context(answer), "recorded on P2"
    end
end
