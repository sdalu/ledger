# frozen_string_literal: true

module LedgerViewer
    module Render
        # Python's html.escape and str.strip, and the text helpers of
        # ledger.py the pages need, ported one for one (a test compares
        # them with the Python on the fixture lines). The regexes carry
        # (?u): Python's \w, \s and \b are Unicode, Ruby's are not.
        module Text
            ESCAPES = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;",
                        '"' => "&quot;", "'" => "&#x27;" }.freeze
            SPACE = /\A[[:space:]\x1c-\x1f]+|[[:space:]\x1c-\x1f]+\z/
            TAIL = /[[:space:]\x1c-\x1f]+\z/
            BLANKS = /[[:space:]\x1c-\x1f]+/
            LINE_ENDS = /\r\n|[\n\r\v\f\x1c-\x1e\u0085\u2028\u2029]/

            CHOICES = /(?u)\bchoices: (.+?)(?=\s+(?:—|mockup:)|\n?\z)/
            ITEMS = /(?u)(?<= — )items: (.+?)(?=\s+(?:—|mockup:)|\n?\z)/
            MOCKUP_REF = %r{(?u)\bmockup:[ ](?!pending\b)
                            ([\w.-]+(?:/[\w.-]+)*)}x
            PENDING = /(?u)\bmockup: pending \((P\d+)\)/
            BY = /(?u)\b(?:by: P\d+|see: [CDFP]\d+(?:, [CDFP]\d+)*)\b/
            QFIELD = /(?u)[ ]—[ ]
                      (problem|risk|recommend|choices|items|by|see):[ ]|
                      (?:[ ]—[ ])?(?=mockup:[ ])/x
            CASE = %w[problem risk recommend].freeze
            RISK_RATING = %r{\A(\d+)/10(?: — |\z)}

            module_function

            def escape(text) = text.to_s.gsub(/[&<>"']/, ESCAPES)

            def strip(text) = text.to_s.gsub(SPACE, "")

            def rstrip(text) = text.to_s.sub(TAIL, "")

            # A title cut at `limit` characters, the cut marked.
            def shorten(text, limit)
                return text if text.length <= limit

                "#{rstrip(text[0, limit - 3])}…"
            end

            # Python's str.split(): on runs of white space, none empty.
            def words(text) = text.to_s.split(BLANKS).reject(&:empty?)

            # Python's str.splitlines().
            def splitlines(text)
                parts = text.split(LINE_ENDS, -1)
                parts.pop if parts.last == ""
                parts
            end

            # Python's urllib.parse.quote: UTF-8 bytes, `/` kept.
            def quote(text)
                text.b.gsub(%r{[^A-Za-z0-9_.\-~/]}n) do |byte|
                    format("%%%<byte>02X", byte: byte.ord)
                end.force_encoding("UTF-8")
            end

            # 'Short title: the detail — field: …' -> [title, the rest].
            def title_of(text)
                first = text.partition(" — ").first
                head, sep, = first.partition(": ")
                if sep.empty? || strip(head).empty?
                    return [strip(first), strip(detail(text, first.length))]
                end

                [strip(head), strip(detail(text, head.length + 2))]
            end

            def detail(text, from) = text[from..].sub(/\A[ —]+/, "")

            # [[key, start, marker end, end]] of the case fields.
            def case_fields(text)
                marks = text.to_enum(:scan, QFIELD).map { Regexp.last_match }
                marks.each_with_index.filter_map do |mark, i|
                    next unless CASE.include?(mark[1])

                    follow = marks[i + 1]&.begin(0) || text.length
                    [mark[1], mark.begin(0), mark.end(0), follow]
                end
            end

            def case_of(text)
                case_fields(text).to_h do |key, _, from, to|
                    [key, strip(text[from...to])]
                end
            end

            def strip_case(text)
                text = text.dup
                case_fields(text).reverse_each do |_, from, _, to|
                    text = text[0...from] + text[to..]
                end
                text
            end

            # [rating or nil, the text after it].
            def risk_rating(text)
                text = strip(text)
                found = RISK_RATING.match(text)
                found ? [found[1].to_i, strip(found.post_match)] : [nil, text]
            end

            # A question as the reader sees it: its directives are drawn
            # as buttons and pictures, so not printed.
            def question_text(text)
                text = strip_case(text)
                [PENDING, MOCKUP_REF, ITEMS, CHOICES, BY].each do |rx|
                    text = text.gsub(rx, "")
                end
                parts = text.split(" — ").map { strip(it) }.reject(&:empty?)
                parts.empty? ? strip(text) : parts.join(" — ")
            end

            # ' · risk N/10' for a rated risk, '' for an unrated one.
            def risk_clause(text)
                rating = risk_rating(text).first
                rating ? " · risk #{rating}/10" : ""
            end

            # '2026-11-19 10:38:45' -> '25 min', '3 h', '2 days'; '' when
            # it is not a time.
            def waited(since, now: Time.now)
                time = local_time(since) or return ""
                minutes = [0, (now - time).to_i / 60].max
                return "#{minutes} min" if minutes < 60
                return "#{minutes / 60} h" if minutes < 48 * 60

                "#{minutes / 1440} days"
            end

            def local_time(text)
                found = /\A(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\z/
                        .match(text.to_s)
                found && Time.new(*found.captures.map(&:to_i))
            rescue ArgumentError
                nil
            end
        end
    end
end
