# frozen_string_literal: true

require_relative "helper"

# `noticed`: a line under `Out of scope, noticed`.
class NoticedTest < CommandCase
    def test_a_line_is_added_and_printed
        out = ok("noticed", BETA, " a side thing ")
        assert_equal "- a side thing\n", out.lines.first
        assert_equal ["- a side thing"], db[:noticed].select_map(:line)
        assert_includes markdown, "Out of scope, noticed:\n- a side thing\n"
    end

    def test_a_dry_run_writes_nothing
        before = state
        assert_includes ok("noticed", BETA, "x", "--dry-run"),
                        "dry run: nothing written"
        assert_equal before, state
    end

    def test_a_text_with_a_line_break_is_refused
        assert_refused("noticed", BETA, "a\nb", "the text holds a line break")
    end

    def test_an_empty_text_is_refused
        assert_refused("noticed", BETA, " ", "the text is empty")
    end
end
