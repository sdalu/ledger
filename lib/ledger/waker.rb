# frozen_string_literal: true

require "json"

require "ledger"

module Ledger
    # The waker (docs/journal.md, section 8): a ledger switched on, an
    # entry from the user pending on it, and a session of its directory
    # idle, get one doorbell line in that session -- on its messaging
    # socket while it lives, else through `claude --resume ID --bg`.
    # This file holds what the command, the viewer and the loop share:
    # the switch, the doorbell's words, the budget and the record of
    # the line format (config/doorbell.json).
    module Waker
        # Minutes a session's last turn end must be old before a wake;
        # LEDGER_WAKER_IDLE_MINUTES overrides.
        IDLE_MINUTES = 10
        IDLE_ENV = "LEDGER_WAKER_IDLE_MINUTES"
        # Wakes per ledger: at most PER_HOUR in an hour, PER_DAY in a day.
        PER_HOUR = 2
        PER_DAY = 8
        HOUR_MS = 3_600_000
        DAY_MS = 24 * HOUR_MS
        # The line format, as the probe established it, and the Claude
        # Code version it was established on.
        RECORD = File.expand_path("../../config/doorbell.json", __dir__)
        # The placeholder the record's line carries for the doorbell text.
        TEXT = "TEXT"

        module_function

        def idle_minutes(env = ENV)
            value = env.fetch(IDLE_ENV, nil)
            return IDLE_MINUTES if value.nil?
            return value.to_i if value.match?(/\A[1-9]\d*\z/)

            raise Refused, "#{IDLE_ENV}=#{value}: a whole number of " \
                           "minutes, 1 or more"
        end

        # The doorbell's words for the ADDRESSES of one session, and
        # nothing else.
        def text(addresses)
            runs = addresses.map { "ledger inbox #{it}" }
            "ledger: an entry from the user waits on " \
                "#{addresses.join(", ")}; run #{runs.join(", ")}"
        end

        # The ledger at ADDRESS switched on or off, in one event
        # (`waker`, its argv the word) that undo can take back.
        def switch(journal, address, on, actor: Write.actor)
            word = on ? "on" : "off"
            Write.run(journal, address, "waker", [word], actor:) do |change|
                change.update(:ledgers, change.ledger_id, waker: on)
                change.summary = "waker #{word}"
                on
            end
        end

        # The wakes of a ledger, newest first.
        def wakes(db, ledger_id)
            db[:wakes].where(ledger_id:).order(Sequel.desc(:id)).all
        end

        # Whether LEDGER_ID may be woken at NOW (ms): fewer than PER_HOUR
        # wakes in the hour before, fewer than PER_DAY in the day before.
        def within_budget?(db, ledger_id, now)
            mine = db[:wakes].where(ledger_id:)
            mine.where { at > now - HOUR_MS }.count < PER_HOUR &&
                mine.where { at > now - DAY_MS }.count < PER_DAY
        end

        # The record of the line format: { "claude_version", "line", … }.
        def record(path = RECORD)
            JSON.parse(File.read(path))
        rescue Errno::ENOENT
            raise Refused, "no doorbell record at #{path}: run " \
                           "bin/ledger-waker --probe"
        end

        # The line the socket takes for TEXT, built from the record's
        # LINE (its TEXT placeholder replaced), newline-terminated.
        def line(text, line = record.fetch("line"))
            "#{JSON.generate(fill(line, text))}\n"
        end

        def fill(value, text)
            case value
            when TEXT then text
            when Hash then value.transform_values { fill(it, text) }
            when Array then value.map { fill(it, text) }
            else value
            end
        end
    end
end
