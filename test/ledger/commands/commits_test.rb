# frozen_string_literal: true

require "json"

require_relative "helper"

# `piece P<n> --commits SHA[,SHA...]`: the commits that landed a piece,
# appended, deduplicated, validated, shown, in the JSON and undone; and
# `check --final` warning of a piece given its commit word with none.
class CommitsTest < CommandCase
    FIRST = "a1b2c3d"
    SECOND = "e4f5a6b"

    def setup
        super
        ok("piece", BETA, "new", "--title", "Try the sort", "--route",
           "sonnet, effort: low", "--status", "verified", "--verified-by",
           "me", "--evidence", "suite green", "--no-picture",
           "a wording change", "--awaits", "commit", "--problem",
           "the sort is not committed", "--risk", "2/10 — a small change")
    end

    def piece(*) = ok("piece", BETA, "P1", *)
    def held = db[:piece_commits].order(:position).select_map(:sha)

    def test_ids_are_appended_and_shown_on_the_line
        out = piece("--commits", "#{FIRST},#{SECOND}")

        assert_includes out, "— commits: #{FIRST}, #{SECOND}"
        assert_equal [FIRST, SECOND], held
    end

    def test_a_later_call_appends_and_never_replaces
        piece("--commits", FIRST)
        piece("--commits", SECOND)

        assert_equal [FIRST, SECOND], held
    end

    def test_a_duplicate_is_ignored
        piece("--commits", "#{FIRST},#{FIRST.upcase}")
        piece("--commits", "#{SECOND},#{FIRST}")

        assert_equal [FIRST, SECOND], held
    end

    def test_a_bad_id_is_refused_and_nothing_is_written
        ["abc123", "a1b2c3dz", "a" * 41].each do |bad|
            assert_refused("piece", BETA, "P1", "--commits", "#{FIRST},#{bad}",
                           "--commits #{bad}: 7 to 40 hex digits")
        end
        assert_refused("piece", BETA, "P1", "--commits", " ",
                       "--commits takes SHA")
        assert_empty held
    end

    def test_the_ids_are_an_empty_list_in_the_json_until_there_are_some
        item = JSON.parse(ok("show", BETA, "P1", "--json"))["item"]

        assert_equal [], item["commits"]
        piece("--commits", FIRST)
        item = JSON.parse(ok("show", BETA, "P1", "--json"))["item"]

        assert_equal [FIRST], item["commits"]
    end

    def test_a_piece_without_commits_shows_no_line
        refute_includes piece("--plan", "sort by name"), "commits"
    end

    def test_the_write_is_undone
        piece("--commits", FIRST)
        ok("undo", BETA)

        assert_empty held
    end

    def word_given
        ok("word", BETA, "P1", "--word", "commit")
    end

    def final = cli("check", "--final", BETA)[1]

    def test_final_warns_of_a_commit_word_with_no_commit
        word_given

        assert_includes final, "warn final-commits -- P1 given its commit " \
                               "word, no commit"
    end

    def test_final_is_quiet_once_a_commit_is_held
        word_given
        piece("--commits", FIRST)

        assert_includes final, "ok   final-commits"
    end

    def test_final_is_quiet_for_a_piece_not_given_the_word
        assert_includes final, "ok   final-commits"
    end

    def test_the_warning_never_fails_the_check
        word_given

        assert_includes final, "FAIL final-criteria"
        refute_includes final, "FAIL final-commits"
    end
end
