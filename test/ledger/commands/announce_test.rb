# frozen_string_literal: true

require "json"

require_relative "piece_test"

# `piece P<n> --announce FILE`: a dispatch's ANNOUNCE block stored
# parsed, one piece_assessments row a call, shown on the piece's line
# and by `show PATH P<n>`, undone like any write.
class AnnounceCase < PieceCase
    DASH = "—"
    WHICH = "sonnet, effort: medium #{DASH} highest axis: stakes (low)".freeze
    RISK = "2/10 #{DASH} a fabricated commit #{DASH} caught by " \
           "check-answer.py".freeze
    MODE = "attended; Fable: refused; spawn: no"

    def setup
        super
        add
    end

    # The shelf's fixture block, a label changed or dropped by FIELDS
    # (nil drops it).
    def block(**fields)
        lines = { WHAT: "parse the grammar", WHY: "separable #{DASH} one file",
                  WHICH:, RISK: "  #{RISK}", MODE: }.merge(fields).compact
        "ANNOUNCE\n#{lines.map { |label, text| "#{label}: #{text}" }
                         .join("\n")}\n"
    end

    def file(text)
        File.join(@dir, "announce-#{text.hash.abs}.txt")
            .tap { File.write(it, text) }
    end

    def announce(text = block, target = "P1")
        ok("piece", BETA, target, "--announce", file(text))
    end

    def rows = db[:piece_assessments].order(:id).all

    # The one row, asserted alone.
    def only
        assert_equal 1, rows.size
        rows.first
    end
end

# The block parsed into its columns, each form the grammar allows.
class AnnounceParseTest < AnnounceCase
    def test_the_command_prints_one_line
        assert_equal "assessment recorded on #{BETA} P1\n", announce
    end

    def test_the_shelf_fixture_block_is_stored_parsed
        announce
        row = only
        assert_equal ["sonnet", "medium", "stakes", "low", 2, RISK, MODE,
                      true],
                     row.values_at(:model, :effort, :axis, :axis_level,
                                   :risk_rating, :risk_text, :mode,
                                   :mode_attended)
        assert_equal ["parse the grammar", "separable #{DASH} one file",
                      block],
                     row.values_at(:what, :why, :block)
    end

    def test_the_row_is_of_its_write_event
        announce
        event = db[:events].order(:id).last
        assert_equal [event[:id], @beta, row[:id]],
                     only.values_at(:event_id, :ledger_id, :piece_id)
    end

    def test_an_effort_and_an_axis_left_out_are_absent
        announce(block(WHICH: "gpt-6.2-sol", MODE: "unattended"))
        assert_equal ["gpt-6.2-sol", nil, nil, nil, false],
                     only.values_at(:model, :effort, :axis, :axis_level,
                                    :mode_attended)
    end

    def test_a_risk_without_a_rating_is_stored_unrated
        announce(block(RISK: "a fabricated commit #{DASH} caught by a test"))
        assert_equal [nil, "a fabricated commit #{DASH} caught by a test"],
                     only.values_at(:risk_rating, :risk_text)
    end

    def test_an_older_axis_is_lower_cased_and_kept
        announce(block(WHICH: "opus, effort: high #{DASH} highest axis: " \
                              "Novelty (high)"))
        assert_equal %w[opus high novelty high],
                     only.values_at(:model, :effort, :axis, :axis_level)
    end

    def test_the_block_ends_at_the_first_blank_line
        announce("#{block}\nBRIEF\nTask: t\n")
        assert_equal block, only[:block]
    end

    def test_stdin_is_read_for_a_dash
        $stdin = StringIO.new(block)
        ok("piece", BETA, "P1", "--announce", "-")
        assert_equal "sonnet", only[:model]
    ensure
        $stdin = STDIN
    end

    def test_the_session_is_kept_when_known
        ENV["CLAUDE_CODE_SESSION_ID"] = "s9"
        announce
        assert_equal "s9", only[:session]
    end
end

# What is refused: exit 2, the reason a sentence on the last line, and
# nothing written.
class AnnounceRefusalTest < AnnounceCase
    def refused_with(text, message, *argv)
        before = state
        code, out, err = cli("piece", BETA, "P1", "--announce", file(text),
                             *argv)
        assert_equal 2, code, out
        assert_equal "piece: #{message}", err.lines(chomp: true).last
        assert_match(/\.\z/, message)
        assert_equal before, state, "a refusal wrote"
    end

    def test_a_block_without_the_announce_line
        refused_with(block.delete_prefix("ANNOUNCE\n"),
                     "the block does not open with the line ANNOUNCE.")
    end

    def test_a_block_without_a_risk_line
        refused_with(block(RISK: nil),
                     "the block has no RISK line; it needs WHAT, WHY, " \
                     "WHICH, RISK and MODE.")
    end

    def test_a_label_twice_an_unknown_line_and_a_mode
        refused_with("#{block}WHAT: again\n", "the block gives WHAT twice.")
        refused_with("#{block}NOTE: x\n",
                     "the block's line \"NOTE: x\" is not LABEL: text, " \
                     "with a label of WHAT, WHY, WHICH, RISK or MODE.")
        refused_with(block(MODE: "maybe; spawn: no"),
                     "the MODE line opens with \"maybe\", not attended or " \
                     "unattended.")
    end

    def test_a_which_line_of_another_shape
        refused_with(block(WHICH: "sonnet, effort: huge"),
                     "the WHICH line \"sonnet, effort: huge\" does not read " \
                     "MODEL[, effort: E] #{DASH} highest axis: AXIS " \
                     "(low|mid|high).")
    end

    def test_an_unknown_piece_and_other_flags
        before = state
        code, _out, err = cli("piece", BETA, "P9", "--announce", file(block))
        assert_equal [2, "piece: there is no P9 under Pieces in #{BETA}.\n"],
                     [code, err]
        refused_with(block, "--announce goes alone: drop --title.",
                     "--title", "x")
        assert_equal before, state
    end
end

# One row a call, shown and undone.
class AnnounceRowsTest < AnnounceCase
    LINE = "- P1 [planned] sonnet, effort: medium #{DASH} Build the " \
           "parser #{DASH} dispatched: ".freeze

    def test_two_identical_calls_are_two_rows_and_undo_removes_one
        2.times { announce }
        assert_equal 2, rows.size
        assert_equal 1, rows.map { it.except(:id, :event_id) }.uniq.size
        ok("undo", BETA)
        assert_equal 1, rows.size
    end

    def test_the_piece_line_counts_the_dispatches_and_shows_the_last
        announce
        announce(block(WHICH: "opus", RISK: "unrated"))
        assert_includes markdown, "#{LINE}2× (last: opus)\n"
        ok("undo", BETA)
        assert_includes markdown, "#{LINE}1× (last: sonnet, medium, " \
                                  "stakes low, risk 2/10)\n"
    end

    def test_show_lists_each_assessment_with_its_time
        announce
        announce(block(WHICH: "gpt-6.2-sol", RISK: "r"))
        times = db[:events].order(:id).last(2)
                           .map { Ledger::Render::Json.time(it[:at]) }
        assert_equal ["assessment: #{times[0]}, sonnet, effort: medium, " \
                      "axis: stakes (low), risk: 2/10, attended",
                      "assessment: #{times[1]}, gpt-6.2-sol, risk: unrated, " \
                      "attended"], shown
    end

    def shown
        ok("show", BETA, "P1").lines(chomp: true).grep(/\Aassessment: /)
    end

    def test_show_json_carries_the_assessments
        announce
        item = JSON.parse(ok("show", BETA, "P1", "--json"))["item"]
        assert_equal [{ "rating" => 2, "text" => RISK }, "stakes"],
                     item["assessments"][0].values_at("risk", "axis")
    end
end

# `stats`, by assessment: P1 dispatched once under stakes and verified
# at the first pass; P2 dispatched under ambiguity, returned for depth,
# dispatched again under stakes and verified.
class AnnounceStatsTest < AnnounceCase
    OUT = ["--status", "out", "--session", "s1"].freeze
    DONE = ["--status", "verified", "--verified-by", "me", "--evidence",
            "tests pass"].freeze
    AMBIGUITY = "opus, effort: high #{DASH} highest axis: ambiguity " \
                "(mid)".freeze
    STAKES = { dispatches: 2, pieces: 1, verified_first: 1,
               returns: {} }.freeze
    OTHER = { dispatches: 1, pieces: 1, verified_first: 0,
              returns: { depth: 1 } }.freeze
    HEAD = ["dispatches", "pieces", "verified first", "returns"].freeze

    def setup
        super
        ok("piece", BETA, *NEW, *ROUTE)
        announce
        ok("piece", BETA, "P1", *OUT)
        ok("piece", BETA, "P1", *DONE)
        returned
    end

    def returned
        announce(block(WHICH: AMBIGUITY), "P2")
        ok("piece", BETA, "P2", *OUT)
        ok("piece", BETA, "P2", "--status", "planned", "--cause", "depth")
        announce(block, "P2")
        ok("piece", BETA, "P2", *OUT)
        ok("piece", BETA, "P2", *DONE)
    end

    def assessments
        JSON.parse(ok("stats", BETA, "--json"),
                   symbolize_names: true)[:assessments]
    end

    def test_the_groups_by_axis_and_by_model_as_json
        assert_equal({ by_axis: [{ axis: "ambiguity", **OTHER },
                                 { axis: "stakes", **STAKES }],
                       by_model: [{ model: "sonnet", **STAKES },
                                  { model: "opus", **OTHER }] },
                     assessments)
    end

    def test_the_section_by_assessment
        lines = ok("stats", BETA).lines(chomp: true)
        section = lines.drop_while { it != "by assessment" }
        assert_equal([["by assessment"], ["highest axis", *HEAD],
                      ["ambiguity", "1", "1", "0/1", "depth 1"],
                      ["stakes", "2", "1", "1/1", "-"], [],
                      ["model", *HEAD],
                      ["sonnet", "2", "1", "1/1", "-"],
                      ["opus", "1", "1", "0/1", "depth 1"]],
                     section.map { it.split(/ {2,}/) })
    end

    def test_no_section_without_a_dispatch_announced
        db[:piece_assessments].delete
        refute_includes ok("stats", BETA), "by assessment"
    end
end
