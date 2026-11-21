# frozen_string_literal: true

require_relative "helper"

# `choice`: an option added to an open question or dropped from it, the
# grammar kept and open-picker passed afterwards.
class ChoiceTest < CommandCase
    def setup
        super
        ask("Which palette wins?", "Palette choice",
            "A = warm | B = cold")
    end

    def ask(question, title, choices)
        argv = [question, "--title", title, "--problem", "colours clash",
                "--risk", "2/10 — a redraw", "--no-picture", "words alone"]
        argv += ["--choices", choices, "--recommend", "A, warmer"] if choices
        ok("ask", BETA, *argv)
    end

    def labels = db[:question_choices].order(:position).select_map(:label)

    def test_an_option_is_added
        out = ok("choice", BETA, "O1", "--add", "C = grey; dull")
        assert_includes out.lines.first, "choices: A = warm | B = cold | " \
                                         "C = grey; dull"
        assert_equal %w[A B C], labels
    end

    def test_an_option_is_dropped_by_its_folded_label
        ok("choice", BETA, "O1", "--add", "C = grey")
        ok("choice", BETA, "O1", "--drop", " c ")
        assert_equal %w[A B], labels
    end

    def test_the_target_is_an_open_question
        assert_refused("choice", BETA, "P1", "--add", "C = grey",
                       "the target is O<n>")
        assert_refused("choice", BETA, "O5", "--add", "C = grey",
                       "O5 is not asked under Open in #{BETA}")
    end

    def test_a_question_without_choices
        ask("Which font wins?", "Font choice", nil)
        assert_refused("choice", BETA, "O2", "--add", "C = grey",
                       "O2 has no `choices:`; ask it with --choices")
    end

    def test_one_of_add_or_drop
        assert_refused("choice", BETA, "O1", "give one of --add, --drop")
        assert_refused("choice", BETA, "O1", "--add", "C = x", "--drop", "A",
                       "give one of --add, --drop")
    end

    def test_the_option_grammar
        assert_refused("choice", BETA, "O1", "--add", "C",
                       "--add takes `LABEL = what it does`")
        assert_refused("choice", BETA, "O1", "--add", "a = again",
                       "two options share a label")
        assert_refused("choice", BETA, "O1", "--drop", "Z",
                       "--drop Z: no such option (A, B)")
    end

    def test_open_picker_runs_after_the_edit
        assert_refused("choice", BETA, "O1", "--drop", "B",
                       "open-picker -- O1: one option is no choice")
    end

    def test_a_dry_run_prints_the_card
        before = state
        out = ok("choice", BETA, "O1", "--add", "C = grey", "--dry-run")
        assert_includes out, "picker O1: 3 options"
        assert_equal before, state
    end
end
