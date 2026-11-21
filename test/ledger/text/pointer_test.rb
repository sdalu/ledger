# frozen_string_literal: true

require "minitest/autorun"

require "ledger/text/pointer"

# The kinds of a fact's pointer and a constraint's where, and the where
# of a constraint's line.
class PointerTest < Minitest::Test
    Pointer = Ledger::Text::Pointer

    def test_a_url
        assert_equal "url", Pointer.kind("https://claude.ai/artifact/Qx")
        assert_equal "url", Pointer.kind("http://example.org")
    end

    def test_a_path_with_or_without_lines
        ["lib/climat_control/web/shell.rb:67", "doc/calendar.md:97-110",
         "~/Repos/ledger", "TODO.md", "rork:/root/Cthulhu"].each do |text|
            assert_equal "path", Pointer.kind(text), text
        end
    end

    def test_a_turn
        assert_equal "turn", Pointer.kind("turn 6")
        assert_equal "turn", Pointer.kind("turn 55 (writes are entries)")
    end

    def test_free_text
        ["ssh rork git status", "memory no-legacy", "turn", "0.2.1",
         "the user (turn 179)", "https://x.org and more"].each do |text|
            assert_equal "text", Pointer.kind(text), text
        end
    end

    def test_a_constraints_where
        assert_equal "turn 6", Pointer.where('"no legacy" — turn 6',
                                             "no legacy")
        assert_nil Pointer.where("refactor skill", "no legacy")
    end
end
