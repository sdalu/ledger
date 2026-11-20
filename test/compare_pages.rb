#!/usr/bin/env ruby
# frozen_string_literal: true

# compare_pages.rb -- the Ruby viewer's page against the Python viewer's,
# byte for byte once what legitimately differs is set aside.
#
#     bundle exec ruby test/compare_pages.rb [--token T] index [ROOT...]
#     bundle exec ruby test/compare_pages.rb [--part top] ledger [ROOT...]
#
# Renders the page twice over the same ledgers: with the Python viewer
# (test/support/python_render.py imports ledger-serve.py by path and calls
# its render function) and with the Ruby port (LedgerViewer::Render,
# called directly, no sign-in). With no ROOT it builds the fixture set of
# test/support/fixture_set.sh in a scratch directory and removes it after.
#
# `ledger` compares the page of every ledger found, the forms carrying
# one fixed token. With `--part top` only the top half is compared: the
# page from its start up to the opening tag of its section of unfinished
# pieces, `<h2 id="flight">` (a page with no such section, because
# nothing is unfinished, asked or sent, is cut at the opening tag of the
# messages, `<h2 id="inbox">`; an unreadable ledger's page is whole).
#
# Exit 0 when the two are equal after normalisation, 1 when they differ
# (the first differing lines are printed), 2 when it cannot run.
#
# Normalised, and nothing else (every rule is applied to both pages):
#   1. the token: the literal TOKEN given with --token becomes TOKEN
#      (the index carries none; a ledger page always does, so the
#      comparison gives its own);
#   2. a waited duration, as a clock reads it at the moment of the run:
#      the text of <span class="wait">..</span>, and "unfiled for N min",
#      "longest N h" and the like, become DURATION;
#   3. a clock time: "today HH:MM" and "sent HH:MM" become CLOCK;
#   4. the tip-N counters: renumbered by first appearance on each page.
#      Python's counter is process-wide, Ruby's starts at 1 per page, so
#      the numbers differ and the order of the tips is what is compared.
# Every other byte is compared as it is, the data-stamp included.

require "fileutils"
require "json"
require "open3"
require "optparse"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ledger_viewer"
require_relative "support/page_compare"

USAGE = "usage: compare_pages.rb [--token TOKEN] [--part top] " \
        "index|ledger [ROOT...]"
# What a ledger page's forms carry, on both sides; set aside as TOKEN.
FORM_TOKEN = "form-token-0123456789abcdef"

# The two renderings: each a {page name => its html}.
class Comparison
    HERE = __dir__
    SCRIPTS = File.expand_path("../../scripts", HERE)

    def initialize(roots, part)
        @roots = roots
        @part = part
    end

    def python(kind)
        args = kind == "index" ? ["index"] : ["ledger", FORM_TOKEN]
        out, err, status = Open3.capture3(
            "python3", File.join(HERE, "support", "python_render.py"),
            *args, *@roots
        )
        abort "python_render.py: #{err}" unless status.success?
        kind == "index" ? { "index" => out } : cut(JSON.parse(out))
    end

    def ruby(kind)
        renderer = LedgerViewer::Render::Renderer.new(config)
        entries = LedgerViewer::Ledgers.new(@roots).all
        return { "index" => renderer.index(entries) } if kind == "index"

        entries.to_h { [it.id, ledger(renderer, entries, it)] }
    end

    private

    def ledger(renderer, entries, entry)
        return renderer.ledger_top(entries, entry, FORM_TOKEN) if
            @part == "top"

        renderer.ledger(entries, entry, FORM_TOKEN)
    end

    def cut(pages)
        return pages unless @part == "top"

        pages.transform_values { Cut.top(it) }
    end

    def config
        LedgerViewer::Config.new(
            roots: @roots, session_secret: "x" * 40, bind: "127.0.0.1:1",
            store: "/nonexistent/users.json",
            ledger_py: File.join(SCRIPTS, "ledger.py"), python: "python3",
            dump_timeout: 20, session_days: 1, tls_dir: "/nonexistent/tls",
            root: File.expand_path("..", HERE)
        )
    end
end

def fixture_roots(dir)
    ledger = File.join(Comparison::SCRIPTS, "ledger.py")
    script = File.join(__dir__, "support", "fixture_set.sh")
    out, status = Open3.capture2e({ "ledger" => ledger }, "sh", script, dir)
    abort "fixture_set.sh failed:\n#{out}" unless status.success?
    [dir]
end

# 0 when every page is equal after normalisation, else 1.
def compare(roots, kind, part, token)
    comparison = Comparison.new(roots, part)
    python = comparison.python(kind)
    ruby = comparison.ruby(kind)
    token ||= FORM_TOKEN
    return missing(python, ruby) unless python.keys.sort == ruby.keys.sort

    python.keys.map { same?(it, python, ruby, token) }.all? ? 0 : 1
end

def same?(name, python, ruby, token)
    left = Normalise.page(python[name], token)
    right = Normalise.page(ruby[name], token)
    return puts("#{name}: equal (#{left.bytesize} bytes)") || true if
        left == right

    puts "#{name}:", Report.first_difference(left, right)
end

def missing(python, ruby)
    puts "the two find different ledgers",
         "  python: #{python.keys.sort.inspect}",
         "  ruby:   #{ruby.keys.sort.inspect}"
    1
end

token = nil
part = nil
OptionParser.new do |opts|
    opts.banner = USAGE
    opts.on("--token TOKEN") { token = it }
    opts.on("--part PART", %w[top]) { part = it }
end.parse!
kind = ARGV.shift
abort USAGE unless %w[index ledger].include?(kind)
abort USAGE if part && kind == "index"

if ARGV.empty?
    Dir.mktmpdir("compare-pages") do |dir|
        exit compare(fixture_roots(dir), kind, part, token)
    end
else
    exit compare(ARGV.map { File.expand_path(it) }, kind, part, token)
end
