# frozen_string_literal: true

require "open3"

require "ledger/hooks/journal_name"
require "ledger/hooks/places"

module Ledger
    # What the practice did, as countable rows of `outcomes`
    # (docs/journal.md, section 1): a refusal, a flag on or off, a Stop
    # hook's verdict. The rows go in their own short transaction, after a
    # refused write has rolled back, and the recorder never raises: a
    # failure is one line on ERR (none when ERR is nil, as a hook's output
    # must not change), and no journal file means nothing written. Under
    # the bundle it writes through Sequel; a fast-path hook, standard
    # library alone, through the sqlite3 program as stamp does.
    #
    #     Ledger::Outcomes.record(kind: "refusal", rule: "pieces-order",
    #                             address:, ref: "P3", detail: "...")
    #
    # A row's ledger is its `ledger_id`, else the live ledger at its
    # `address` (place, name), else the one live ledger at its `places`
    # (none when there are several); `live: true` writes it only when a
    # live ledger sits at its places, `changed: true` only when its detail
    # differs from the last row of its kind and rule for its session and
    # ledger. Its session is `session:`, else CLAUDE_CODE_SESSION_ID.
    module Outcomes
        # The program; LEDGER_SQLITE overrides.
        SQLITE = "/usr/local/bin/sqlite3"
        BUSY_MS = 2000
        COLUMNS = "ledger_id, session, at, kind, rule, ref, detail"
        LIVE = "FROM ledgers WHERE closed_at IS NULL AND place IN (%s)"

        module_function

        def record(err: $stderr, **row) = write([row], err:)

        # ROWS written in one transaction; -> true when they were.
        def write(rows, err: $stderr)
            path = Hooks::JournalName.current.path
            return false if rows.empty? || !File.file?(path)

            run(path, rows.map { insert(it) })
            true
        rescue StandardError => e
            err&.puts "ledger: outcome not recorded: " \
                      "#{e.message.lines.first.to_s.chomp}"
            false
        end

        # A Stop hook's verdict, VERDICT (sent-back, let-through) and why,
        # when a live ledger sits at its places; a let-through only when
        # it differs from the hook's last row for the session and ledger,
        # so a quiet session writes nothing per turn.
        def hook(name, payload, verdict, why)
            record(kind: "hook", rule: name, places: Hooks::Places.of(payload),
                   session: session(payload), live: true,
                   changed: verdict == "let-through",
                   detail: "#{verdict}: #{why}", err: nil)
        end

        def run(path, statements)
            return sequel(path, statements) if defined?(::Sequel::Database)

            program(path, statements)
        end

        def sequel(path, statements)
            db = Sequel.sqlite(path, timeout: BUSY_MS)
            db.transaction(mode: :immediate) { statements.each { db.run(it) } }
        ensure
            db&.disconnect
        end

        def program(path, statements)
            sql = ["BEGIN IMMEDIATE;", *statements, "COMMIT;"].join("\n")
            out, status = Open3.capture2e(ENV.fetch("LEDGER_SQLITE", SQLITE),
                                          "-bail", "-cmd",
                                          ".timeout #{BUSY_MS}", path, sql)
            raise out.lines.first.to_s.chomp unless status.success?
        end

        def insert(row)
            sql = "INSERT INTO outcomes (#{COLUMNS}) SELECT #{values(row)}"
            only = [("EXISTS (SELECT 1 #{live(row[:places])})" if row[:live]),
                    (changed(row) if row[:changed])].compact
            return "#{sql};" if only.empty?

            "#{sql} WHERE #{only.join(" AND ")};"
        end

        # The row's detail is not that of the last row of its kind and
        # rule for its session and ledger.
        def changed(row)
            "(SELECT detail FROM outcomes WHERE kind = #{text(row[:kind])} " \
                "AND rule = #{text(row[:rule])} AND session IS " \
                "#{text(row_session(row))} AND ledger_id IS #{ledger(row)} " \
                "ORDER BY id DESC LIMIT 1) IS NOT #{text(row[:detail])}"
        end

        def row_session(row) = row.fetch(:session) { session }

        # The row's values as SQL, in COLUMNS' order.
        def values(row)
            [ledger(row), text(row_session(row)), Integer(row[:at] || now),
             *row.fetch_values(:kind, :rule).map { text(it) },
             *row.values_at(:ref, :detail).map { text(it) }].join(", ")
        end

        def ledger(row)
            return Integer(row[:ledger_id]) if row[:ledger_id]

            address = row[:address]
            return by_address(address) if address
            return by_places(row[:places]) if row[:places]

            "NULL"
        end

        def by_address(address)
            "(SELECT id FROM ledgers WHERE closed_at IS NULL AND " \
                "place = #{text(address.place)} AND " \
                "name = #{text(address.name)})"
        end

        # The one live ledger at PLACES; NULL when none or several.
        def by_places(places)
            "(SELECT CASE WHEN count(*) = 1 THEN max(id) END " \
                "#{live(places)})"
        end

        def live(places) = format(LIVE, places.map { text(it) }.join(", "))

        # VALUE as an SQL literal: NULL, or quoted with ' doubled.
        def text(value)
            value.nil? ? "NULL" : "'#{value.to_s.gsub("'", "''")}'"
        end

        # A hook PAYLOAD's session_id, else CLAUDE_CODE_SESSION_ID; nil
        # when neither names one.
        def session(payload = {})
            id = payload["session_id"].to_s.strip
            id = ENV.fetch("CLAUDE_CODE_SESSION_ID", "").strip if id.empty?
            id.empty? ? nil : id
        end

        def now = Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
    end
end
