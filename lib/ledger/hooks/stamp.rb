# frozen_string_literal: true

require "open3"

require "ledger/hooks/journal_name"

module Ledger
    module Hooks
        # Stop: the turn's end stamped in session_stops, the waker's test
        # of idle (docs/journal.md, section 8). The standard library alone,
        # no bundle: the row goes in through the sqlite3 program, the
        # session id checked to be a bare id before it enters the SQL. No
        # journal, no table (a journal before migration 005), no program:
        # nothing is written and the stop goes through.
        module Stamp
            # The program; LEDGER_SQLITE overrides.
            SQLITE = "/usr/local/bin/sqlite3"
            ID = /\A[0-9A-Za-z-]{1,64}\z/
            BUSY_MS = 2000

            module_function

            def call(payload, now: clock)
                id = payload["session_id"].to_s
                path = JournalName.current.path
                stamp(path, id, now) if ID.match?(id) && File.file?(path)
                Answer.pass
            end

            def stamp(path, id, now)
                sql = "INSERT INTO session_stops (session_id, at) " \
                      "VALUES ('#{id}', #{Integer(now)}) ON CONFLICT " \
                      "(session_id) DO UPDATE SET at = excluded.at;"
                Open3.capture2e(ENV.fetch("LEDGER_SQLITE", SQLITE), "-bail",
                                "-cmd", ".timeout #{BUSY_MS}", path, sql)
            end

            def clock
                Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
            end
        end
    end
end
