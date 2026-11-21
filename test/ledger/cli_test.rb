# frozen_string_literal: true

require "open3"

require_relative "commands/helper"

# The dispatch: usage, words not built yet, refusals of the write path as
# the CLI prints them, and the launcher that finds the bundle.
class CliTest < CommandCase
    BIN = File.expand_path("../../bin/ledger", __dir__)

    # Help is an answer, on standard output with 0: no word, help, --help
    # and -h list every word under a section with its summary.
    def test_help_is_an_answer_however_asked
        [[], ["help"], ["--help"], ["-h"]].each do |argv|
            code, out, err = cli(*argv)
            assert_equal [0, ""], [code, err], argv.inspect
            assert_includes out, "Usage: ledger WORD"
        end
    end

    def test_help_lists_every_word_with_its_summary
        _, out, = cli("help")
        Ledger::CLI::WORDS.each do |word|
            command = Ledger::Commands.const_get(word.capitalize)
            refute_empty command::SUMMARY, word
            assert_match(/^  #{word} /, out, word)
        end
        assert_equal Ledger::CLI::WORDS.sort,
                     Ledger::Help::SECTIONS.values.flatten.sort
    end

    # A word's help, asked either way: its synopsis and summary, and
    # nothing read or written whatever else the words hold.
    def test_a_word_s_help_shows_its_synopsis_and_summary
        [%w[help piece], %w[piece --help], %w[piece BETA new -h]].each do |argv|
            code, out, = cli(*argv)
            assert_equal 0, code, argv.inspect
            assert_includes out, "usage: ledger piece PATH new|P<n>"
            assert_includes out, "add a piece or change one"
            assert_match(/--status VALUE +planned, out/, out)
        end
    end

    def test_every_option_is_described
        Ledger::CLI::WORDS.each do |word|
            _, out, = cli(word, "--help")
            out.lines.grep(/^ +--?\w/).each do |line|
                assert_match(/\S {2,}\S/, line, "#{word}: #{line.strip}")
            end
        end
    end

    def test_an_unknown_word_is_refused
        assert_refused("frobnicate", "frobnicate: unknown command")
        assert_refused("help", "frobnicate", "frobnicate: unknown command")
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

    # A directory given for an address: the refusal names the form and
    # the live ledgers at that directory or under it.
    def test_a_directory_is_refused_with_the_ledgers_under_it
        ok("new", "/work/beta/sub/LEDGER-web.md", *GOAL)
        _, _, err = cli("show", "/work")

        assert_includes err, "not a ledger address: /work"
        assert_includes err, "LEDGER.md or LEDGER-NAME.md"
        assert_includes err, "live ledgers under /work:"
        assert_includes err, "  /work/beta/LEDGER.md\n"
        assert_includes err, "  /work/beta/sub/LEDGER-web.md\n"
    end

    # A wrong name in the right directory: the ones that are there.
    def test_a_missing_ledger_names_its_neighbours
        _, _, err = cli("show", "/work/beta/LEDGER-other.md")

        assert_includes err, "no live ledger at /work/beta/LEDGER-other.md"
        assert_includes err, "  /work/beta/LEDGER.md\n"
    end

    # Nothing near: the refusal is the one line it was.
    def test_nothing_near_adds_nothing
        _, _, err = cli("show", "/elsewhere")

        assert_includes err, "not a ledger address: /elsewhere"
        refute_includes err, "live ledgers"
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
