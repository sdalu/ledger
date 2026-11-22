# frozen_string_literal: true

require "ledger/waker"
require "ledger/waker/bell"
require "ledger/waker/claude"

module Ledger
    module Waker
        # One look of the waker. The ledgers switched on with an entry
        # pending (an entry, nothing else: a stalled piece is no entry),
        # their sessions, and each session woken at most once, one line
        # naming its ledgers still within the budget, when:
        #
        # - its last turn end (session_stops) is older than the idle
        #   minutes, and no wake was made since;
        # - `claude agents` lists it idle (interactive) or done
        #   (background), or not at all.
        #
        # The way: the socket for a session listed idle (never a resume:
        # its process lives); a resume for one listed done (a background
        # session's process exits after its turn) or not listed. Every
        # wake is a wakes row per ledger named, whatever its outcome.
        class Pass
            # One wake as the loop prints it.
            Wake = Data.define(:session_id, :ledger_ids, :path, :outcome)

            def initialize(journal, claude: Claude.new, line: nil,
                           idle_minutes: Waker.idle_minutes)
                @journal = journal
                @db = journal.db
                @claude = claude
                @line = line || Waker.record.fetch("line")
                @idle_ms = idle_minutes * 60_000
            end

            # -> the wakes made, at NOW (ms).
            def call(now = Write.now)
                waiting = waiting_ledgers
                return [] if waiting.empty?

                listed = @claude.agents
                sessions(waiting.keys).filter_map do |session_id, ledger_ids|
                    wake(session_id, ledger_ids, waiting, listed, now)
                end
            end

            private

            # ledger_id => address, the ledgers on with an entry pending.
            def waiting_ledgers
                pending = @db[:inbox_entries].where(taken_id: nil)
                                             .select(:ledger_id)
                @db[:ledgers].where(waker: true, closed_at: nil,
                                    id: pending)
                             .order(:id).all
                             .to_h { [it[:id], address(it)] }
            end

            def address(row)
                Address.new(place: row[:place], name: row[:name]).to_s
            end

            # session_id => its ledger ids among LEDGER_IDS.
            def sessions(ledger_ids)
                @db[:session_ledgers].where(ledger_id: ledger_ids)
                                     .order(:session_id, :ledger_id).all
                                     .group_by { it[:session_id] }
                                     .transform_values do |rows|
                    rows.map { it[:ledger_id] }
                end
            end

            def wake(session_id, ledger_ids, waiting, listed, now)
                session = @db[:sessions].where(session_id:).first
                return unless session && idle?(session_id, now)

                ids = ledger_ids.select { Waker.within_budget?(@db, it, now) }
                seen = listed[session_id]
                return if ids.empty? || (seen && !seen.idle?)

                text = Waker.text(ids.map { waiting.fetch(it) })
                deliver(session, seen, ids, text, now)
            end

            # The last turn end older than the idle minutes, no wake since.
            def idle?(session_id, now)
                stop = @db[:session_stops].where(session_id:).get(:at)
                return false unless stop && now - stop >= @idle_ms

                @db[:wakes].where(session_id:).where { at > stop }.empty?
            end

            def deliver(session, seen, ids, text, now)
                path, outcome =
                    seen&.live? ? ring(session, text) : resume(session, text)
                record(session[:session_id], ids, path, outcome, now)
            end

            # A socket is written only for a session listed live: the
            # file of one that exited may name another process's by now.
            def ring(session, text)
                failure = Bell.ring(session[:socket], Waker.line(text, @line))
                ["socket", failure ? "failed: #{failure}" : "posted"]
            end

            def resume(session, text)
                resumed = @claude.resume(session[:session_id], text,
                                         session[:cwd])
                return ["resume", "failed: #{resumed.failure}"] unless
                    resumed.short
                return %w[resume resumed] if
                    session[:session_id].start_with?(resumed.short)

                ["resume", copied(session[:session_id], resumed.short)]
            end

            # A resume that started a copy: the session's record (and its
            # ledgers, by the cascade) moves to the copy's id, so the next
            # wake reaches the live one. Its stop is not carried: the copy
            # is idle once its own stamp says so.
            def copied(session_id, short)
                full = listed_ids.find { it&.start_with?(short) }
                return "copied #{short} (its full id not listed)" unless full

                @journal.transaction { move(session_id, full) }
                "copied #{full}"
            end

            # The ids `claude agents` lists, none when that call fails.
            def listed_ids
                @claude.agents.keys
            rescue Claude::Failed
                []
            end

            # A copy its own session-start recorded already keeps its row;
            # the old one goes.
            def move(from, to)
                old = @db[:sessions].where(session_id: from)
                return old.update(session_id: to) if
                    @db[:sessions].where(session_id: to).empty?

                @db[:session_ledgers].where(session_id: from).delete
                old.delete
            end

            def record(session_id, ids, path, outcome, now)
                @journal.transaction do
                    ids.each do |ledger_id|
                        @db[:wakes].insert(ledger_id:, session_id:, at: now,
                                           path:, outcome:)
                    end
                end
                Wake.new(session_id:, ledger_ids: ids, path:, outcome:)
            end
        end
    end
end
