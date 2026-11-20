# frozen_string_literal: true

require "test_helper"
require "open3"

# The helpers ported from ledger.py and ledger-serve.py say what the
# Python says, on the lines the orchestration fixture holds and on the
# edge cases a ledger line can carry.
class TextTest < Minitest::Test
    PROBE = File.expand_path("support/text_probe.py", __dir__)

    # The lines tests/viewer-fixture.sh's ledger holds (questions,
    # pieces, a criterion, a fact), as ledger-dump.py gives them.
    FIXTURE = [
        "Calendar entry priority: what range does an entry take? — " \
        "problem: the API accepts any priority, the doc says 1-16 — " \
        "risk: 5/10 — a client sending 40 is ranked last — choices: " \
        "A = document 1-16 (one line) | B = cap at 16 (~4 files: route, " \
        "tests), the file named in your comment — recommend: A, nothing " \
        "sends above 16 — see: F1 — mockup: page.html — mockup: flow.txt",
        "Header items: take each? — problem: the header is crowded — " \
        "risk: 5/10 — a busy header — items: S1 | S2 — choices: A = as " \
        "drawn | drop = remove it — recommend: A, it reads best — by: P2",
        "Release timing: Ship now or with the release? — problem: the " \
        "fix is ready — risk: 5/10 — early readers — choices: A = now | " \
        "B = with the release — recommend: A, it only documents",
        "document the priority range", "fix the reorder",
        "<a check something other than opinion can pass> — evidence:",
        "- F1: leftovers, not re-checked: V1 radii (menu.css:28); V2 one " \
        "shadow (room.css:211); S1 empty slot — doc/r.md:3"
    ].freeze

    EDGES = [
        "", "   ", "Title only", "A: b — c: d — e", " — odd start",
        "title — mockup: pending (P3) — x", "x — mockup: a/b.png — y",
        "O1: a — risk: 7/10 — why — choices: A = x | B = y — by: P2",
        "q — items: S1 | S2 — choices: A | B — see: C1, D2",
        "5/10", "5/10 — fine", "x 5/10 — no", "10/10 — all",
        "é — ünï: côde `a*b*` **bold** _it_ *em* $x*y$ [P1](#piece-P1)",
        "a & b < c > \"d\" 'e' https://example.com/a?b=1&c=2 end",
        "[bad](javascript:x) [ok](https://example.com) **a**b _a_b",
        " nbsp  — 　wide　", "tab\there — x",
        "P1", "O12", "p1", "AB1", "Z"
    ].freeze

    def test_the_ruby_helpers_say_what_the_python_says
        texts = FIXTURE + EDGES
        out, status = Open3.capture2("python3", PROBE,
                                     stdin_data: JSON.generate(texts))

        assert_predicate status, :success?
        texts.zip(JSON.parse(out)).each { |text, want| check(text, want) }
    end

    def check(text, want)
        got = ruby_view(text)
        want.each do |key, expected|
            assert_equal expected, got.fetch(key), "#{key} of #{text.inspect}"
        end
    end

    def ruby_view(text)
        t = LedgerViewer::Render::Text
        { "escape" => t.escape(text), "strip" => t.strip(text),
          "title_of" => t.title_of(text), "case_of" => t.case_of(text),
          "strip_case" => t.strip_case(text),
          "risk_rating" => t.risk_rating(text),
          "question_text" => t.question_text(text),
          "risk_clause" => t.risk_clause(text),
          "inline" => LedgerViewer::Render::Markup.inline(text),
          "chip" => LedgerViewer::Render::Helpers.chip(text) }
    end

    def test_a_wait_is_in_minutes_hours_then_days
        t = LedgerViewer::Render::Text
        now = Time.new(2026, 11, 20, 12, 0, 0)

        assert_equal "25 min", t.waited("2026-11-20 11:35:00", now:)
        assert_equal "3 h", t.waited("2026-11-20 09:00:00", now:)
        assert_equal "2 days", t.waited("2026-11-18 11:00:00", now:)
        assert_equal "0 min", t.waited("2026-11-20 12:30:00", now:)
        assert_empty t.waited("", now:)
        assert_empty t.waited(nil, now:)
    end
end
