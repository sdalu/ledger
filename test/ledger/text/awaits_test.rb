# frozen_string_literal: true

require "minitest/autorun"

require "ledger/text/awaits"

# Cases of awaited, scope_words, awaits_label, from
# check-ledger-awaits.sh (words, one spelling, other, refusals).
class AwaitsTest < Minitest::Test
    Awaits = Ledger::Text::Awaits

    def test_start
        assert_equal [["start", ""]], Awaits.parse("start")
    end

    def test_one_spelling_whatever_was_typed
        assert_equal [["commit", ""], ["deploy", ""]],
                     Awaits.parse("commit,  deploy")
        assert_equal "commit, deploy",
                     Awaits.label(Awaits.parse("commit,  deploy"))
    end

    def test_other_with_what
        want = [["other", "look at the shots on the phone"]]
        assert_equal want,
                     Awaits.parse("other (look at the shots on the phone)")
    end

    def test_comma_inside_parentheses_stays
        assert_equal [["commit", ""], ["other", "look, then go"]],
                     Awaits.parse("commit, other (look, then go)")
    end

    def test_every_word_of_the_list
        assert_equal %w[start commit deploy push merge],
                     Awaits.parse("start, commit, deploy, push, merge")
                           .map(&:first)
    end

    def test_unknown_word_refused
        assert_nil Awaits.parse("go")
        assert_nil Awaits.parse("commit, go")
    end

    def test_bare_other_refused
        assert_nil Awaits.parse("other")
        assert_nil Awaits.parse("other ()")
        assert_nil Awaits.parse("other ( )")
    end

    def test_nothing_is_nil
        assert_nil Awaits.parse("")
        assert_nil Awaits.parse(" , ")
    end

    def test_label_with_other
        words = Awaits.parse("start, other (look at the shots)")
        assert_equal "start, other (look at the shots)", Awaits.label(words)
    end

    def test_finish_words
        assert Awaits.finish?("commit")
        assert Awaits.finish?("merge")
        refute Awaits.finish?("start")
        refute Awaits.finish?("other")
    end

    def test_scope_words
        assert_equal [["commit", "merge it"], ["deploy", "ship it"]],
                     Awaits.scope_words("commit = merge it | deploy = ship it")
    end

    def test_scope_words_refused
        assert_nil Awaits.scope_words("commit")
        assert_nil Awaits.scope_words("commit = ")
        assert_nil Awaits.scope_words(" = x")
        assert_nil Awaits.scope_words("commit = a | ")
        assert_nil Awaits.scope_words("")
    end

    def test_scope_text_round_trips
        text = "commit = merge it | deploy = ship it"
        assert_equal text, Awaits.scope_text(Awaits.scope_words(text))
    end
end
