# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# A text drawn from the clock alone is marked data-age, so that the page
# script neither redraws nor flags a part for it.
class AgeMarkTest < Minitest::Test
    Age = LedgerViewer::Render::Age

    def test_a_bracketed_age_becomes_a_data_age_element
        html = Age.mark("<p>waiting #{Age.of("3 h")}, since 10:00</p>")
        assert_equal "<p>waiting <span data-age>3 h</span>, since 10:00</p>",
                     html
    end

    def test_an_empty_age_brackets_nothing
        assert_equal "", Age.of("")
        assert_equal "stalled", Age.mark("stalled#{Age.of("")}")
    end

    def test_inside_a_tag_the_brackets_are_dropped
        html = Age.mark(%(<a title="out · #{Age.of("2 h")}">x</a>))
        assert_equal %(<a title="out · 2 h">x</a>), html
    end
end

# Each place the viewer draws a wait age or "today", as the page has it.
class AgePageTest < ViewerTest
    include LedgerFixture

    def build_fixture
        super
        ledger("piece", "new", "--route", "sonnet, effort: low",
               "--title", "fix the reorder", "--status", "verified",
               "--verified-by", "me", "--evidence", "it builds",
               "--problem", "the fix is not committed",
               "--risk", "2/10 — it waits", "--plan", "commit it")
        ledger("piece", "P1", "--awaits", "commit",
               "--no-picture", "a commit has no look")
    end

    def page(path = "/l/#{@lid}")
        sign_in
        https path
        last_response.body
    end

    def test_the_ledger_page_marks_its_ages_and_nothing_is_left_bracketed
        html = page
        assert_match(%r{class="meta">waiting <span data-age>0 min</span>, },
                     html[%r{id="q-O1".*?</li>}m])
        assert_match(%r{class="meta">[^<]*waiting <span data-age>0 min</span>},
                     html[%r{id="p-P1".*?</li>}m])
        assert_match(%r{longest <span data-age>0 min</span>}, html)
        assert_match(/Ledger updated <span data-age>today \d\d:\d\d</, html)
        refute_match(/[\u{E000}\u{E001}]/, html)
    end

    def test_the_index_marks_its_wait
        html = page("/")
        assert_match(%r{<span class="wait"><span data-age>0 min</span>},
                     html)
        refute_match(/[\u{E000}\u{E001}]/, html)
    end
end
