# frozen_string_literal: true

module LedgerViewer
    module Render
        # HTML escaping, white-space stripping and the text helpers the
        # pages need.
        module Text
            ESCAPES = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;",
                        '"' => "&quot;", "'" => "&#x27;" }.freeze
            SPACE = /\A[[:space:]\x1c-\x1f]+|[[:space:]\x1c-\x1f]+\z/
            TAIL = /[[:space:]\x1c-\x1f]+\z/
            BLANKS = /[[:space:]\x1c-\x1f]+/
            LINE_ENDS = /\r\n|[\n\r\v\f\x1c-\x1e\u0085\u2028\u2029]/

            RISK_RATING = %r{\A(\d+)/10(?: — |\z)}
            # A local time as an inbox entry has it, or an ISO time with
            # its offset as the journal gives one.
            TIME = /\A(\d{4})-(\d\d)-(\d\d)[ T](\d\d):(\d\d):(\d\d)
                    ([+-]\d\d:\d\d)?\z/x

            module_function

            def escape(text) = text.to_s.gsub(/[&<>"']/, ESCAPES)

            def strip(text) = text.to_s.gsub(SPACE, "")

            def rstrip(text) = text.to_s.sub(TAIL, "")

            # A title cut at `limit` characters, the cut marked.
            def shorten(text, limit)
                return text if text.length <= limit

                "#{rstrip(text[0, limit - 3])}…"
            end

            # Words: runs of white space split, none empty.
            def words(text) = text.to_s.split(BLANKS).reject(&:empty?)

            # Lines, split on every Unicode line boundary, no empty last one.
            def splitlines(text)
                parts = text.split(LINE_ENDS, -1)
                parts.pop if parts.last == ""
                parts
            end

            # Percent-encoding of the UTF-8 bytes, `/` kept.
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

            # [rating or nil, the text after it].
            def risk_rating(text)
                text = strip(text)
                found = RISK_RATING.match(text)
                found ? [found[1].to_i, strip(found.post_match)] : [nil, text]
            end

            # ' · risk N/10' for a rated risk, '' for an unrated one.
            def risk_clause(text)
                rating = risk_rating(text).first
                rating ? " · risk #{rating}/10" : ""
            end

            # '2026-11-19 10:38:45' (local) or an ISO time with its offset
            # -> '25 min', '3 h', '2 days'; '' when it is not a time.
            def waited(since, now: Time.now)
                time = local_time(since) or return ""
                minutes = [0, (now - time).to_i / 60].max
                return "#{minutes} min" if minutes < 60
                return "#{minutes / 60} h" if minutes < 48 * 60

                "#{minutes / 1440} days"
            end

            def local_time(text)
                found = TIME.match(text.to_s) or return
                *parts, zone = found.captures
                parts = parts.map(&:to_i)
                zone ? Time.new(*parts, zone) : Time.new(*parts)
            rescue ArgumentError
                nil
            end

            # A time as the page writes it: 'YYYY-MM-DD HH:MM', local; ''
            # when it is not a time.
            def minute(text)
                local_time(text)&.localtime&.strftime("%Y-%m-%d %H:%M").to_s
            end
        end
    end
end
