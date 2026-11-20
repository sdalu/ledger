# frozen_string_literal: true

require "test_helper"
require "open3"

# The helpers the ledger page adds to the index's, said as the Python
# says them, on strings a ledger can carry: field cuts, links, times,
# names of pictures, Markdown blocks, ids that link with a tip.
class PageTextTest < Minitest::Test
    PROBE = File.expand_path("support/page_probe.py", __dir__)
    R = LedgerViewer::Render

    TEXTS = [
        "", "  ", "a b  c", "a\nb\n\nc\n\n", "x\r\ny z",
        "é ü/ñ ~ a b.png", "a%41 +", "A" * 59, "A" * 60, "B" * 61,
        "é#{"é" * 70}", "A = keep as is", "A", "  A  = b", "= x",
        "commit = merge it | deploy = ship it", "commit = a | = b",
        "commit | deploy = x", "commit = a | ", "",
        "q — see: F1, C2 — mockup: x", "q — see: F1 — by: P2 — risk: 5/10",
        "q — done when: x — evidence: y — see: P1", "q — after: P1, P2",
        "q — for: D1 — awaits: commit, deploy — plan: do",
        "problem: x — plan: y — scope: z", "F1, C2", "F1,C2", "P1, P2, P3",
        "x", "P1, x", "2026-11-19 16:02:11", "2026-11-19T16:02", "16:02",
        "2026-11-19", "2026-11-19 25:00", "2026-02-30 10:00",
        "2026-11-19T16:02:11+01:00", "2026-11-19T16:02:11Z",
        "2026-11-19T16:02:11.123456", "nonsense", "a.b.png", ".png", "a.",
        "..", "dir/a.svg", "a", "7", "3", "4", "10",
        "text with [P1](#piece-P1) and [O2](#q-O2) and [D3](#crit-D3) " \
        "and [P9](#piece-P9) and [P1 more](#piece-P1) and [P1](#piece-P2) " \
        "and [P1](https://example.com)",
        "- a\n- b\n\n1. x\n2) y\n\n> quote\n>> deeper\n\n```\ncode & <b>\n" \
        "```\npara one\nline two\n\n* star\n- mixed\n1. num\n- back",
        "```\nunclosed", "> a\n> b\nplain", "line\r\nnext", "\n\n\n",
        "  - indented\n    - more", "3. three\n4. four"
    ].freeze

    def test_the_helpers_say_what_the_python_says
        out, status = Open3.capture2("python3", PROBE,
                                     stdin_data: JSON.generate(TEXTS))

        assert_predicate status, :success?
        TEXTS.zip(JSON.parse(out)).each { |text, want| check(text, want) }
    end

    def check(text, want)
        got = ruby_view(text)
        want.each_key do |key|
            next if key == "rows" && !text.match?(/\A\d+\z/)

            same(want[key], got.fetch(key), "#{key} of #{text.inspect}")
        end
    end

    def same(want, got, message)
        return assert_nil(got, message) if want.nil?

        assert_equal want, got, message
    end

    def ruby_view(text)
        plain_view(text).merge(
            "titled" => scope.inline(text),
            "md_block" => R::Blocks.new(scope).html(text),
            "rows" => numbers(text)
        )
    end

    def numbers(text)
        return [] unless text.match?(/\A\d+\z/)

        [R::Helpers.risk_band(text.to_i)]
    end

    def plain_view(text)
        { "words" => R::Text.words(text),
          "splitlines" => R::Text.splitlines(text),
          "quote" => R::Text.quote(text),
          "shorten" => R::Text.shorten(text, 60),
          "option_code" => R::Terms.option_code(text),
          "scope_words" => R::Terms.scope_words(text),
          "split_fields" => R::Terms.split_fields(text),
          "link_see" => R::Terms.link_ids("see", text),
          "clock" => R::Clock.clock(text),
          "splitext" => [R::Terms.stem(text), R::Terms.ext(text)] }
    end

    # A fresh scope for each string, so that the tips count from 1 as the
    # probe's do.
    def scope
        R::Scope.new(nil).page({ "P1" => "A title", "O2" => "x" * 100,
                                 "D3" => "" })
    end
end
