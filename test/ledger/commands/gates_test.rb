# frozen_string_literal: true

require "json"

require_relative "piece_test"

# `piece P<n> --gate "NAME: STATE (DETAIL)"`: one row per name, a later
# state replacing it with its own time; `piece P<n> --report FILE`: the
# status line and up to 12 lines, one report a piece, alone or in the
# hand-back's call. Both on the piece line, in show and in its JSON.
class GatesTest < PieceCase
    def setup
        super
        add
    end

    def piece(*) = ok("piece", BETA, "P1", *)
    def gates = db[:piece_gates].order(:id).select_map(%i[name state detail])
    def report = db[:piece_reports].select_map(%i[status body])

    def file(text)
        File.join(@dir, "report-#{text.hash.abs}.txt")
            .tap { File.write(it, text) }
    end

    def json
        JSON.parse(ok("show", BETA, "--json"))["pieces"].first
    end

    def test_a_gate_is_stored_with_its_detail_and_shown_on_the_line
        piece("--gate", "rubocop: passed")
        out = piece("--gate", "unit: failed (2 failures in piece_test.rb)")

        assert_equal [["rubocop", "passed", nil],
                      ["unit", "failed", "2 failures in piece_test.rb"]],
                     gates
        assert_includes out, "— gates: rubocop passed, unit failed " \
                             "(2 failures in piece_test.rb)"
    end

    def test_a_later_state_replaces_the_row_of_its_name_and_its_time
        piece("--gate", "unit: running")
        first = db[:piece_gates].get(:event_id)
        piece("--gate", "unit: passed")

        assert_equal [["unit", "passed", nil]], gates
        refute_equal first, db[:piece_gates].get(:event_id)
    end

    def test_a_gate_not_of_the_shape_is_refused
        refused("P1", "--gate", "unit: done", "--gate takes \"NAME: STATE")
        refused("P1", "--gate", ": passed", "--gate takes")
        refused("P1", "--gate", "unit passed", "--gate takes")
    end

    def test_a_gate_is_undone_like_any_write
        piece("--gate", "unit: running")
        piece("--gate", "unit: failed (boom)")
        ok("undo", BETA)

        assert_equal [["unit", "running", nil]], gates
    end

    def test_a_report_keeps_its_status_line_and_twelve_lines
        lines = (1..14).map { "line #{it}" }
        text = "DONE_WITH_CONCERNS\n#{lines.join("\n")}\n"
        out = piece("--report", file(text))

        assert_equal [["DONE_WITH_CONCERNS", lines.first(12).join("\n")]],
                     report
        assert_includes out, "— report: DONE_WITH_CONCERNS"
    end

    def test_a_later_report_replaces_it_trailing_blank_lines_dropped
        piece("--report", file("BLOCKED\nwhy\n"))
        piece("--report", file("DONE\nall green\n\n\n"))

        assert_equal [["DONE", "all green"]], report
    end

    def test_a_report_without_a_status_line_or_a_file_is_refused
        refused("P1", "--report", file("\nDONE\n"), "the status word, is empty")
        refused("P1", "--report", File.join(@dir, "none.txt"),
                "--report cannot read")
    end

    def test_the_hand_back_stores_the_report_and_sets_the_piece_back
        ok("piece", BETA, "P1", "--status", "out", "--session", "s1")
        out = piece("--status", "back", "--handback", "--report",
                    file("DONE\nall green\n"))

        assert_equal "hand-back recorded on #{BETA} P1\n", out
        assert_equal "back", row[:status]
        assert_equal [["DONE", "all green"]], report
    end

    def test_a_piece_not_out_keeps_its_status_and_takes_the_report
        out = piece("--status", "back", "--handback", "--report",
                    file("DONE\n"))

        assert_equal "P1 is planned; report recorded, the status unchanged\n",
                     out
        assert_equal "planned", row[:status]
        assert_equal [["DONE", nil]], report
    end

    def test_show_gives_the_gates_and_the_report
        piece("--gate", "unit: failed (boom)")
        piece("--report", file("DONE_WITH_CONCERNS\none\ntwo\n"))
        shown = ok("show", BETA, "P1")

        assert_match(/^gate: unit failed \(boom\), \d{4}-/, shown)
        assert_match(/^report: DONE_WITH_CONCERNS, \d{4}-.*\n  one\n  two$/,
                     shown)
    end

    def test_json_gives_the_gates_and_the_report
        piece("--gate", "unit: failed (boom)")
        piece("--report", file("DONE_WITH_CONCERNS\none\ntwo\n"))
        gates = json["gates"].map { it.values_at("name", "state", "detail") }

        assert_equal [%w[unit failed boom]], gates
        assert_equal ["DONE_WITH_CONCERNS", %w[one two]],
                     json["report"].values_at("status", "lines")
    end
end
