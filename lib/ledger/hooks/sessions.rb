# frozen_string_literal: true

require "sequel"

require "ledger"
require "ledger/hooks/ledgers"

module Ledger
    module Hooks
        # What session-start records for the waker (docs/journal.md,
        # section 8): the session id, its messaging socket's path (the
        # token beside it in the environment is never read) and its
        # directory, and the live ledgers of that directory, which
        # replace what the session had. A session with no ledger there is
        # not recorded. The journal is never created and never migrated
        # here: no file, or no sessions table, and nothing is written.
        module Sessions
            SOCKET = "CLAUDE_CODE_MESSAGING_SOCKET"
            BUSY_MS = 2000

            module_function

            def record(payload, env: ENV, now: Write.now)
                id = payload["session_id"].to_s
                path = Journal.path
                return if id.empty? || !File.file?(path)

                db = Sequel.sqlite(path, timeout: BUSY_MS, foreign_keys: true)
                write(db, id, payload, env[SOCKET], now) if
                    db.table_exists?(:sessions)
            ensure
                db&.disconnect
            end

            def write(db, id, payload, socket, now)
                places = Ledgers.places(payload)
                ids = db[:ledgers].where(place: places, closed_at: nil)
                                  .order(:id).select_map(:id)
                return if ids.empty?

                row = { socket:, cwd: places.first, at: now }
                db.transaction(mode: :immediate) { replace(db, id, row, ids) }
            end

            # The session row upserted, its ledgers replaced by IDS.
            def replace(db, id, row, ids)
                db[:sessions].insert_conflict(target: :session_id, update: row)
                             .insert(session_id: id, **row)
                ledgers = db[:session_ledgers]
                ledgers.where(session_id: id).delete
                ledgers.import(%i[session_id ledger_id], ids.map { [id, it] })
            end
        end
    end
end
