# frozen_string_literal: true

require "date"

require_relative "text"

module LedgerViewer
    module Render
        # The times a ledger page writes: when a file changed, when an
        # answer was sent, how long it has been unfiled.
        module Clock
            # An ISO 8601 time: date, optional time and offset, `T` or a space.
            ISO = /\A(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d)(?::(\d\d)
                   (?::(\d\d)(?:[.,]\d{1,6})?)?)?)?(Z|[+-]\d\d:?\d\d)?\z/x

            module_function

            # '2026-11-19 10:38:45' (local) or an ISO time with an offset
            # -> 'HH:MM' local, 24-hour; '' when it is not a time.
            def clock(stamp)
                found = ISO.match(Text.strip(stamp.to_s))
                time = found && instant(found)
                time ? time.localtime.strftime("%H:%M") : ""
            rescue ArgumentError
                ""
            end

            def instant(found)
                year, month, day, hour, min, sec, zone = found.captures
                parts = [year, month, day, hour || 0, min || 0, sec || 0]
                        .map(&:to_i)
                return unless valid?(parts)

                zone ? Time.new(*parts, offset(zone)) : Time.new(*parts)
            end

            def valid?(parts)
                year, month, day, hour, min, sec = parts
                Date.valid_date?(year, month, day) &&
                    hour < 24 && min < 60 && sec < 60
            end

            def offset(zone)
                zone == "Z" ? "+00:00" : zone.sub(/(\d\d)(\d\d)\z/, '\1:\2')
            end

            # 'sent HH:MM · unfiled for N min' for an entry no session took.
            def receipt(entry)
                at = (entry["at"] || "").to_s
                time = clock(at)
                wait = Ledger::Text.waited(at)
                [(time.empty? ? "" : "sent #{time}"),
                 (wait.empty? ? "" : "unfiled for #{Age.of(wait)}")]
                    .reject(&:empty?).join(" · ")
            end

            # 'today HH:MM', or the date before the time when it is not
            # today.
            def updated(moment)
                time = Time.at(moment).localtime
                today = time.to_date == Date.today
                Age.of(time.strftime(today ? "today %H:%M" : "%Y-%m-%d %H:%M"))
            end

            # A path under the home directory, with ~ for it.
            def short(path)
                home = Dir.home
                return path unless path == home || path.start_with?("#{home}/")

                "~#{path[home.length..]}"
            end
        end
    end
end
