# frozen_string_literal: true

require "test_helper"
require_relative "support/page_compare"

# The harness sets aside what legitimately differs and nothing else.
class PageCompareTest < Minitest::Test
    def norm(html, token = nil) = Normalise.page(html, token)

    def test_a_waited_duration_and_a_clock_time_are_set_aside
        html = '<span class="wait">13 min</span> today 12:13 sent 09:01 ' \
               "unfiled for 3 h longest 2 days"

        assert_equal '<span class="wait">DURATION</span> today CLOCK ' \
                     "sent CLOCK unfiled for DURATION longest DURATION",
                     norm(html)
    end

    def test_the_token_is_set_aside_only_when_given
        assert_equal "a TOKEN b", norm("a s3cret b", "s3cret")
        assert_equal "a s3cret b", norm("a s3cret b")
    end

    def test_tips_are_renumbered_by_order_of_appearance
        assert_equal norm('id="tip-4" for="tip-7" id="tip-4"'),
                     norm('id="tip-1" for="tip-2" id="tip-1"')
        refute_equal norm('id="tip-1" for="tip-2"'),
                     norm('id="tip-2" for="tip-1"').sub("tip-2", "tip-3")
    end

    def test_a_changed_word_is_not_set_aside
        refute_equal norm("<li>Answer</li>"), norm("<li>Answers</li>")
    end

    def test_the_top_half_ends_where_the_unfinished_section_opens
        page = 'a<h2 id="inbox">i</h2>b<h2 id="flight">f</h2>c'

        assert_equal "a", Cut.top(page)
        assert_equal "a<h2>x</h2>b", Cut.top('a<h2>x</h2>b<h2 id="flight">f')
    end

    def test_a_page_with_no_such_section_is_cut_at_the_messages_or_whole
        assert_equal "a", Cut.top('a<h2 id="inbox">i</h2>')
        assert_equal "<p>whole</p>", Cut.top("<p>whole</p>")
    end

    def test_the_first_difference_is_shown_with_its_line
        report = Report.first_difference("<p>a</p><p>b</p>", "<p>a</p><p>c</p>")

        assert_includes report, "python 4"
        assert_includes report, '"<p>c"'
    end
end
