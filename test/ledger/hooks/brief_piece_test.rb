# frozen_string_literal: true

require_relative "helper"

# brief-piece: a dispatch names the piece it carries out, or says it is
# no piece, while the session has a live ledger.
class BriefPieceTest < HookTest
    def setup
        super
        write("import") do |change|
            piece(change)
            piece(change, status: "out")
            chain(change)
        end
    end

    # P3 follows the out P2; P4 awaits the user's word.
    def chain(change)
        after = piece(change)
        change.insert(:piece_links, piece_id: after, kind: "after",
                                    position: 0, after_id: 2)
        awaiting = piece(change)
        change.insert(:piece_awaits, piece_id: awaiting, position: 0,
                                     word: "start")
    end

    def prompt(header) = "BRIEF\nTask: x\n#{header}\nModel: sonnet\n\nBody"

    def dispatch(text, cwd: PLACE, tool: "Agent", session: "s9")
        answer = hook("brief-piece", tool_name: tool, cwd:,
                                     session_id: session,
                                     tool_input: { prompt: text })
        answer.out && json(answer)["hookSpecificOutput"]
    end

    def denied(header, **) = dispatch(prompt(header), **)

    def reason(header, **) = denied(header, **)["permissionDecisionReason"]

    def test_a_ready_piece_passes
        assert_nil dispatch(prompt("Piece: #{ADDRESS} P1"))
    end

    def test_no_header_is_denied_with_one_sentence
        out = dispatch("BRIEF\nTask: x\n\nPiece: #{ADDRESS} P1")

        assert_equal "deny", out["permissionDecision"]
        assert_match(/has no Piece: header line; add the header line/,
                     out["permissionDecisionReason"])
        assert_equal 1, out["permissionDecisionReason"].scan(/\.\z/).size
    end

    def test_a_prompt_with_no_brief_line_is_denied
        out = dispatch("Piece: #{ADDRESS} P1")

        assert_equal "deny", out["permissionDecision"]
    end

    def test_a_relative_or_non_md_path_is_refused_naming_it
        assert_match(/"LEDGER.md", not absolute/,
                     reason("Piece: LEDGER.md P1"))
        assert_match(%r{"/work/alpha/x.txt", not a .md file},
                     reason("Piece: /work/alpha/x.txt P1"))
        assert_match(/`Piece: P1`/, reason("Piece: P1"))
    end

    def test_a_missing_or_unready_piece_is_denied
        {
            "P9" => "which #{ADDRESS} does not have",
            "P2" => "which is out, neither ready nor out under this session",
            "P3" => "which is planned, neither ready nor out",
            "P4" => "which is planned, neither ready nor out"
        }.each do |ref, why|
            assert_match why, reason("Piece: #{ADDRESS} #{ref}")
        end
        assert_match "no live ledger here",
                     reason("Piece: /work/beta/LEDGER.md P1")
    end

    def test_a_piece_out_under_this_session_passes_another_s_is_denied
        assert_nil denied("Piece: #{ADDRESS} P2", session: "s1")
        assert_match(/P2, which is out, neither ready nor out/,
                     reason("Piece: #{ADDRESS} P2", session: "other"))
        assert_match "P2", reason("Piece: #{ADDRESS} P2", session: "")
    end

    def test_none_with_a_reason_passes_and_without_is_denied
        assert_nil denied("Piece: none — a review, no piece")
        assert_equal "deny", denied("Piece: none —")["permissionDecision"]
        assert_equal "deny", denied("Piece: none")["permissionDecision"]
    end

    def test_no_live_ledger_and_other_tools_pass_silently
        assert_nil dispatch(prompt("Piece: none"), cwd: "/work/beta")
        assert_nil dispatch("anything", cwd: "/work/beta")
        assert_nil dispatch("anything", tool: "Bash")
    end
end
