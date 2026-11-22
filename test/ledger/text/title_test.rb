# frozen_string_literal: true

require "minitest/autorun"

require "ledger/text/title"

# Cases of title_problem, detail_problem and title_of, from
# check-ledger-write.sh (title and detail refusals) and
# check-ledger-vocab.sh (title-of, detail-problem).
class TitleTest < Minitest::Test
    Title = Ledger::Text::Title

    def test_prose_title_passes
        assert_nil Title.problem("Port the parser")
        assert_nil Title.problem("Build the tokenizer")
        assert_nil Title.problem("Calendar priority range")
    end

    def test_empty_title
        assert_equal "the title is empty", Title.problem("  ")
    end

    def test_long_title_refused
        text = "word " * 13
        assert_equal "the title is 64 characters, at most 60",
                     Title.problem(text)
        assert_nil Title.problem("#{"x" * 55} word")
    end

    def test_ids_title_refused
        mostly = "the title is mostly ids; name the subject in words " \
                 "(`Calendar priority range`, not `O13 D1`)"
        assert_equal mostly, Title.problem("C1 C4 D2 K1")
        assert_equal mostly, Title.problem("C1 D2")
        assert_equal mostly, Title.problem("O13 D1")
    end

    def test_one_word_without_an_id_passes
        assert_nil Title.problem("Thing")
        assert_nil Title.problem("Thing's")
    end

    def test_one_word_with_an_id_and_no_word_are_refused
        refute_nil Title.problem("C1 header")
        refute_nil Title.problem("42")
    end

    def test_ids_among_words_passes
        assert_nil Title.problem("Mock the S1 S2 header")
        assert_nil Title.problem("F1 header items")
    end

    def test_colon_title_refused
        assert_equal "the title holds `: `, which starts the detail",
                     Title.problem("Fix: the parser")
    end

    def test_cut_title_refused
        cut = "the title is cut short; say it in fewer words"
        assert_equal cut, Title.problem("Fix the parser…")
        assert_equal cut, Title.problem("Fix the parser...")
    end

    def test_detail_mostly_ids_refused
        why = "the detail is mostly ids; say in words what they stand " \
              "for, or point to them with — see:"
        assert_equal why, Title.detail_problem("C1 C4 D2 K1 K2 O10/O11 once")
        long = "C1 (wording: applies to N of M rooms) C4 D2 K1 K2 K3, " \
               "worktree from main, gates incl. touched front suites; " \
               "C3 and D1 once O10/O11 are answered"
        assert_equal why, Title.detail_problem(long)
    end

    def test_prose_detail_passes
        assert_nil Title.detail_problem(
            "fix the header in D1 and then the footer of C2"
        )
        assert_nil Title.detail_problem("")
    end

    def test_detail_stops_at_its_first_field
        assert_nil Title.detail_problem("fix the header — see: C1 C4 D2 K1")
    end

    def test_split
        assert_equal ["F2 fixes", "C1, C4 — after: P3"],
                     Title.split("F2 fixes: C1, C4 — after: P3")
        assert_equal ["Ship now?", "problem: p"],
                     Title.split("Ship now? — problem: p")
        assert_equal ["no detail", ""], Title.split("no detail")
    end
end
