# frozen_string_literal: true

# The two halves of the comparison that need no process: what is set
# aside before two pages are compared (named in compare_pages.rb's
# header), and how the first difference is shown.

# Where the top half of a ledger page ends: the opening tag of the
# section of unfinished pieces, or, on a page with nothing unfinished,
# nothing waiting and nothing sent (which drops that section), the
# opening tag of the section of messages that follows. A page with
# neither (an unreadable ledger's) is whole.
module Cut
    MARKS = ['<h2 id="flight">', '<h2 id="inbox">'].freeze

    def self.top(html)
        at = MARKS.filter_map { html.index(it) }.min
        at ? html[0...at] : html
    end
end

# One page, normalised.
module Normalise
    DURATION = /\d+ (?:min|h|days)/
    RULES = [
        [%r{(<span class="wait">)[^<]*(</span>)}, '\1DURATION\2'],
        [/\b(unfiled for|longest) #{DURATION}/o, '\1 DURATION'],
        [/\b(today|sent) \d\d:\d\d/, '\1 CLOCK']
    ].freeze

    def self.page(html, token)
        html = html.gsub(token, "TOKEN") if token
        html = RULES.reduce(html) { |text, (rx, to)| text.gsub(rx, to) }
        tips(html)
    end

    def self.tips(html)
        seen = {}
        html.gsub(/\btip-(\d+)\b/) do
            "tip-#{seen[Regexp.last_match(1)] ||= seen.length + 1}"
        end
    end
end

# Where the two pages differ, a line at a time: every tag starts a line.
module Report
    def self.first_difference(python, ruby, context: 3)
        left = lines(python)
        right = lines(ruby)
        at = (0...[left.length, right.length].max)
             .find { left[it] != right[it] }
        show(left, right, at, context)
    end

    def self.lines(html) = html.gsub(/(?=<)/, "\n").lines(chomp: true)

    def self.show(left, right, at, context)
        head = "first difference at line #{at + 1} of the tag-per-line form"
        shown = ([at - context, 0].max..at).reject do |n|
            n < at && left[n] == right[n]
        end
        [head, *shown.flat_map { pair(left, right, it) }].join("\n")
    end

    def self.pair(left, right, n)
        ["  python #{n + 1}: #{left[n].inspect}",
         "  ruby   #{n + 1}: #{right[n].inspect}"]
    end
end
