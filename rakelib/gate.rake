# frozen_string_literal: true

require "open3"
require_relative "partial_gate"

# gate.rake -- a partial gate for the edit loop: only what changed.
#
#   rake gate:partial            changed since HEAD, untracked files too
#   rake gate:partial BASE=main  changed since another commit
#   rake gate:partial FILES="lib/a.rb test/b_test.rb"
#                                these files instead of the diff
#   BROWSER=chrome|firefox|both|none  the browser checks, when a page
#                                file changed (default chrome)
#
# The tests named after the changed files (or requiring them), rubocop on
# the changed Ruby files, one browser when a page changed. It is not the
# gate: `rake` and both browser checks still decide before a commit.

namespace :gate do
    def gate_changed
        given = ENV.fetch("FILES", nil)
        return given.split if given

        base = ENV.fetch("BASE", "HEAD")
        diff, status = Open3.capture2("git", "diff", "--name-only", base, "--")
        abort("gate:partial: git diff against #{base} failed") unless
            status.success?
        diff.split + `git ls-files --others --exclude-standard`.split
    end

    def gate_browsers
        choice = ENV.fetch("BROWSER", "chrome")
        browsers = { "chrome" => %w[chrome], "firefox" => %w[firefox],
                     "both" => %w[chrome firefox], "none" => [] }
        browsers.fetch(choice) do
            abort("gate:partial: BROWSER=#{choice} is not chrome, " \
                  "firefox, both or none")
        end
    end

    def gate_say(selection)
        tests = selection.tests
        puts "tests: #{tests.empty? ? "none" : tests.join(" ")}"
        puts "rubocop: #{selection.linted.length} file(s)"
        return if selection.uncovered.empty?

        puts "no test names: #{selection.uncovered.join(" ")} " \
             "(the full rake covers them)"
    end

    desc "Partial gate: the tests and rubocop for what changed " \
         "(BASE=ref, FILES=..., BROWSER=chrome|firefox|both|none)"
    task :partial do
        browsers = gate_browsers
        selection = PartialGate.select(Dir.pwd, gate_changed)
        gate_say(selection)
        unless selection.tests.empty?
            loader = "ARGV.each { require File.expand_path(it) }"
            sh("ruby", "-Ilib", "-Itest", "-e", loader, *selection.tests,
               verbose: false)
        end
        rubocop_run(selection.linted) unless selection.linted.empty?
        if selection.page
            browsers.each do |browser|
                sh({ "ONLY" => browser }, "ruby", "test/browser_run.rb",
                   verbose: false)
            end
        end
        puts "partial gate passed; the full rake decides before a commit"
    end
end
