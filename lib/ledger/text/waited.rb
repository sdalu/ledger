# frozen_string_literal: true

module Ledger
    # How long something has waited, said the one way the status line,
    # the resume view and the viewer say it: '25 min', '3 h', '2 days'.
    #
    #     Ledger::Text.span(3 * 3_600_000)              # => "3 h"
    #     Ledger::Text.waited("2026-11-19 10:38:45")    # => "2 days"
    module Text
        # A local time as an inbox entry has it, or an ISO time with its
        # offset as the journal gives one.
        TIME = /\A(\d{4})-(\d\d)-(\d\d)[ T](\d\d):(\d\d):(\d\d)
                ([+-]\d\d:\d\d)?\z/x

        module_function

        # A time as TIME reads it -> its span to NOW; '' when it is not a
        # time.
        def waited(since, now: Time.now)
            time = local_time(since) or return ""
            span((now - time).to_i * 1000)
        end

        # MS -> '25 min' under an hour, '3 h' under two days, else
        # '2 days'; a span below 0 is 0 min.
        def span(ms)
            minutes = [0, ms / 60_000].max
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
    end
end
