# frozen_string_literal: true

require_relative "helper"

# An `ask` test: one question's words and case, a refusal of it with
# more flags.
class AskCase < CommandCase
    CASE = ["--problem", "the colours clash", "--risk",
            "2/10 — a redraw"].freeze
    QUESTION = ["Which palette wins?", "--title", "Palette for the panel",
                *CASE].freeze

    def ask(*argv) = ok("ask", BETA, *QUESTION, *argv)

    def refused(*argv, message)
        assert_refused("ask", BETA, *QUESTION, *argv, message)
    end

    def question(n = 1) = db[:questions].where(ledger_id: @beta, n:).first

    def edges
        db[:links].order(:id).select_map(%i[kind from_kind to_kind])
    end
end

# `ask`: a question under Open, its id first, its picture decision, its
# links and its option grammar.
class AskTest < AskCase
    def test_a_question_prints_its_id_then_its_line
        out = ask("--no-picture", "words alone")
        assert_equal ["O1", "- O1: Palette for the panel: Which palette " \
                            "wins? — problem: the colours clash — risk: " \
                            "2/10 — a redraw"], out.lines(chomp: true)[0..1]
        assert_equal ["words alone", 2],
                     question.values_at(:no_picture, :risk_rating)
    end

    def test_choices_items_see_and_a_pending_picture
        ok("piece", BETA, "new", "--title", "Draw the mockup", "--route",
           "haiku, effort: low")
        ask("--choices", "A = warm; slower | B = cold", "--items", "S1 | S2",
            "--recommend", "S1 A, S2 B", "--see", "D1, P1", "--pending", "P1")
        line = markdown.lines.grep(/O1:/).first
        assert_includes line, "— items: S1 | S2 — choices: A = warm; " \
                              "slower | B = cold — recommend: S1 A, S2 B"
        assert_includes line, "— see: D1, P1 — mockup: pending (P1)"
    end

    def test_a_mockup_placed_in_the_journal
        Ledger::Write.run(@journal, BETA, "mockup", []) do |change|
            change.insert(:pictures, name: "panel.svg", path: "",
                                     type: "image/svg+xml", bytes: "<svg/>")
        end
        ask("--mockup", "panel.svg")
        assert_includes markdown, "— mockup: panel.svg"
        refused("--mockup", "other.svg", "--mockup other.svg: no picture " \
                                         "of that name in the journal")
    end

    def test_title_and_detail_rules
        assert_refused("ask", BETA, "Which?", *CASE, "--no-picture", "x",
                       "--title is required")
        assert_refused("ask", BETA, "Which?", "--title", "O13 D1", *CASE,
                       "--no-picture", "x", "ask: the title is mostly ids")
        assert_refused("ask", BETA, "O1 O2 O3", "--title", "Palette choice",
                       *CASE, "--no-picture", "x",
                       "ask: the detail is mostly ids")
    end

    def test_the_case_and_the_question
        assert_refused("ask", BETA, "Which?", "--title", "Palette choice",
                       "--no-picture", "x", "a question gives --problem")
        assert_refused("ask", BETA, " ", "--title", "Palette choice", *CASE,
                       "--no-picture", "x", "the question is empty")
    end

    def test_exactly_one_picture_decision
        refused("say what picture the question has")
        refused("--no-picture", "x", "--pending", "P1",
                "say what picture the question has")
        refused("--no-picture", " ", "--no-picture says why")
    end

    def test_a_pending_piece_must_exist_and_draw
        refused("--pending", "D1", "--pending names a piece, P<n>")
        refused("--pending", "P3", "--pending P3: no such piece")
        ok("piece", BETA, "new", "--title", "Draw the mockup", "--status",
           "kept: not now")
        ok("piece", BETA, "P1", "--status", "dropped", "--route",
           "haiku, effort: low")
        refused("--pending", "P1", "that piece is dropped and will draw")
    end

    def test_by_and_see_name_items_of_this_ledger
        refused("--no-picture", "x", "--by", "D1", "--by names a piece")
        refused("--no-picture", "x", "--by", "P4", "P4 is not this ledger's")
        refused("--no-picture", "x", "--see", "O1", "--see takes C/D/F/P ids")
        ok("piece", BETA, "new", "--title", "Draw the mockup", "--status",
           "dropped", "--route", "haiku, effort: low")
        refused("--no-picture", "x", "--by", "P1",
                "--by P1: that piece is dropped and will prepare nothing")
    end

    def test_option_grammar_and_items_without_choices
        refused("--no-picture", "x", "--choices", "A = go | a = stop",
                "two options share a label")
        refused("--no-picture", "x", "--items", "S1 | S2",
                "--items needs --choices")
    end

    def test_seven_options_warn
        choices = %w[A B C D E F G].map { "#{it} = do #{it}" }.join(" | ")
        _, _, err = cli("ask", BETA, *QUESTION, "--no-picture", "x",
                        "--choices", choices, "--recommend", "A, the first")
        assert_includes err, "ask: warning: 7 options"
    end
end

# `ask --replaces` closing an open question in the same write, and a
# dry run's card.
class AskReplacesTest < AskCase
    def test_replaces_closes_files_and_links
        ask("--no-picture", "x")
        out = ok("ask", BETA, "Which colour wins?", "--title",
                 "Colour for the panel", *CASE, "--no-picture", "x",
                 "--replaces", "O1")
        assert_equal "O2", out.lines.first.chomp
        refute_nil question(1)[:closed_at]
        assert_equal "O1: replaced by O2 (Colour for the panel)",
                     db[:decisions].get(:body)
        assert_equal [%w[answers X O], %w[replaces O O]], edges
    end

    def test_replaces_an_open_question_without_untaken_entries
        refused("--no-picture", "x", "--replaces", "O4",
                "--replaces O4: not asked under Open in #{BETA}")
        ask("--no-picture", "x")
        Ledger::Write.run(@journal, BETA, "inbox", []) do |change|
            change.insert(:inbox_entries, n: 1, at: "2026-11-20 10:00:00",
                                          ref: "O1", payload: "{}")
        end
        refused("--no-picture", "x", "--replaces", "O1",
                "--replaces O1: the viewer holds N1 about it, not taken yet")
    end

    def test_a_dry_run_prints_the_card_and_writes_nothing
        before = state
        out = ok("ask", BETA, *QUESTION, "--no-picture", "x", "--choices",
                 "A = warm | B = cold", "--recommend", "A, warmer",
                 "--dry-run")
        assert_includes out, "dry run: nothing written"
        assert_includes out, "picker O1: 2 options"
        assert_includes out, "  A = warm  <- recommended"
        assert_equal before, state
    end
end
