# frozen_string_literal: true

require "open3"

require_relative "commands/helper"

# The dispatch: usage, words not built yet, refusals of the write path as
# the CLI prints them, and the launcher that finds the bundle.
class CliTest < CommandCase
    BIN = File.expand_path("../../bin/ledger", __dir__)

    def test_no_word_is_a_usage_error
        code, _out, err = cli
        assert_equal 2, code
        assert_includes err, "usage: ledger WORD"
    end

    def test_an_unknown_word_is_refused
        assert_refused("frobnicate", "frobnicate: unknown command")
    end

    def test_every_word_has_its_command
        assert_empty Ledger::CLI::NOT_BUILT
        Ledger::CLI::WORDS.each do |word|
            assert Ledger::Commands.const_defined?(word.capitalize), word
        end
    end

    def test_a_wrong_number_of_arguments_is_a_usage_error
        assert_refused("fact", BETA, "usage: ledger fact PATH TEXT")
        assert_refused("fact", "usage: ledger fact PATH TEXT")
        assert_refused("fact", BETA, "a — b", "c", "usage: ledger fact")
    end

    def test_an_unknown_option_is_a_usage_error
        assert_refused("fact", BETA, "a — b", "--nope", "invalid option")
    end

    def test_a_check_that_got_worse_is_refused_one_line_per_rule
        piece_serving(1)
        assert_refused("criterion", BETA, "D1", "--met", "x",
                       "criterion: refused, criteria-pieces -- D1 met")
    end

    def test_a_missing_ledger_is_refused
        assert_refused("fact", "/work/nowhere/LEDGER.md", "a — b",
                       "fact: no live ledger at /work/nowhere/LEDGER.md")
        assert_refused("fact", "/work/nowhere/notes.md", "a — b",
                       "not a ledger address")
    end

    def test_the_launcher_runs_the_cli_under_the_bundle
        env = { "LEDGER_JOURNAL" => ENV.fetch("LEDGER_JOURNAL") }
        out, status = Open3.capture2e(env, BIN, "status", BETA)
        assert status.success?, out
        assert_match(%r{\AStatus — criteria 0/1}, out)
    end

    def test_the_launcher_refuses_an_interpreter_that_is_not_executable
        out, status = Open3.capture2e({ "LEDGER_RUBY" => "/nonexistent/ruby" },
                                      BIN, "status", BETA)
        assert_equal 1, status.exitstatus
        assert_includes out, "LEDGER_RUBY=/nonexistent/ruby is not executable"
    end
end
