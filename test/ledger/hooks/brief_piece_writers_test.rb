# frozen_string_literal: true

require_relative "helper"

# brief-piece: a writing dispatch needs isolation worktree while another
# piece of the session is out with a writing dispatch.
class BriefPieceWritersTest < HookTest
    READER = "Tools: Read, Grep, Glob"
    WRITER = "Tools: Read, Edit, Write, Bash"

    def setup
        super
        write("import") { |change| 3.times { piece(change, status: "out") } }
    end

    def prompt(ref, tools)
        "BRIEF\nTask: x\nPiece: #{ADDRESS} #{ref}\n#{tools}\n\nBody"
    end

    # The answer's hookSpecificOutput, nil when the dispatch passes.
    def dispatch(ref, tools = WRITER, **input)
        answer = hook("brief-piece", tool_name: "Agent", session_id: "s1",
                                     tool_input: { prompt: prompt(ref, tools),
                                                   **input })
        answer.out && json(answer)["hookSpecificOutput"]
    end

    def test_a_lone_writer_passes
        assert_nil dispatch("P1")
    end

    def test_a_second_writer_without_worktree_is_refused_naming_the_first
        dispatch("P1")
        reason = dispatch("P2")["permissionDecisionReason"]

        assert_match(/\ADispatch refused: it writes without isolation/,
                     reason)
        assert_includes reason, "P1 of #{ADDRESS}"
        assert_equal 1, reason.scan(/\.\z/).size
    end

    def test_a_second_writer_in_a_worktree_passes
        dispatch("P1")

        assert_nil dispatch("P2", isolation: "worktree")
    end

    def test_a_reader_passes_beside_a_writer
        dispatch("P1")

        assert_nil dispatch("P2", READER)
        assert_nil dispatch("P3", "Permissions: read-only, no writes")
    end

    def test_a_reader_is_not_a_writer_for_the_next_dispatch
        dispatch("P1", READER)

        assert_nil dispatch("P2")
    end

    def test_a_writer_whose_piece_is_no_longer_out_does_not_block
        dispatch("P1")
        write("drop") do |change|
            change.update(:pieces, 1, status: "dropped", claimed_by: nil)
        end

        assert_nil dispatch("P2")
    end

    def test_a_writer_alone_again_after_a_refusal_is_still_refused
        dispatch("P1")
        dispatch("P2")

        assert_match(/P1 of/, dispatch("P2")["permissionDecisionReason"])
    end
end
