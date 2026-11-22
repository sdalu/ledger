# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"
require_relative "support/sends"

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

# Texts that carry the age brackets themselves, which only the viewer's
# own Age.of may write: a title, a detail, a comment on the page; the
# stale form's text.
class AgeForgeryTest < ViewerTest
    include LedgerFixture
    include Sends

    FORGED = "\u{E000}x\u{E001}"

    def build_fixture
        ledger("new", *GOAL)
        ledger("ask", "which#{FORGED}?", "--title",
               "Which tool#{FORGED} to use",
               "--problem", "de#{FORGED}tail", "--risk", "5/10 — meh",
               "--choices", "A = one | B = two", "--recommend", "A, simple",
               "--no-picture",
               "a choice of words")
    end

    def page
        sign_in
        https "/l/#{@lid}"
        last_response.body
    end

    def balanced?(html) = html.scan("<span").size == html.scan("</span>").size

    def test_a_title_a_detail_and_a_comment_with_the_brackets_draw_no_tag
        sign_in
        say([%w[ref O1], %w[comment 1], ["text", "no#{FORGED}te"]])
        html = page

        assert_includes html, "Which toolx to use"
        assert_includes html, "dextail"
        assert_includes html, "noxte"
        refute_match(/[\u{E000}\u{E001}]/, html)
        assert balanced?(html)
    end

    def test_the_ages_the_server_draws_still_become_elements
        assert_match(%r{waiting <span data-age>0 min</span>}, page)
    end

    def test_the_stale_form_drops_the_brackets_from_what_was_typed
        sign_in
        say([%w[ref O1], %w[comment 1], ["text", "a#{FORGED}b"]],
            token: "0" * 64)

        assert_includes last_response.body, "Not sent yet"
        assert_includes last_response.body, "axb"
        refute_match(/[\u{E000}\u{E001}]/, last_response.body)
        assert balanced?(last_response.body)
    end
end
