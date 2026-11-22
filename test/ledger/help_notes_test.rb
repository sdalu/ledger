# frozen_string_literal: true

require_relative "commands/helper"

# What the help says of the writers: the ask synopsis and the overview's
# list of writers without --dry-run.
class HelpNotesTest < CommandCase
    def test_the_ask_synopsis_names_its_required_case_flags
        _, out, = cli("ask", "--help")
        usage = out.lines.first
        %w[--problem --risk --recommend].each do |flag|
            assert_includes usage, flag
        end
    end

    def test_the_overview_names_the_writers_without_dry_run
        _, out, = cli("help")
        flat = out.gsub(/\s+/, " ")
        assert_includes flat, "Every writer but new, take, close, mockup, " \
                              "waker and purge takes --dry-run"
    end
end
