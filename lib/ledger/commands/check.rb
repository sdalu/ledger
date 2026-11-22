# frozen_string_literal: true

require "json"

require "ledger/flag_outcomes"

module Ledger
    module Commands
        # `check [--final] [--peek] [--fix-hints] [--json] PATH`: every
        # rule's verdict, then the status line, which beats unless --peek.
        class Check < CLI::Command
            USAGE = "PATH"
            SYNOPSIS = "[--final] [--peek] PATH"
            SUMMARY = "each rule's verdict, then the status line: a " \
                      "heartbeat unless --peek"

            private

            def flags(parser)
                parser.on("--final", "judge the finish too") do
                    @opts[:final] = true
                end
                parser.on("--peek", "a read, not counted as a heartbeat") do
                    @opts[:peek] = true
                end
                parser.on("--fix-hints", "a hint after each FAIL") do
                    @opts[:hints] = true
                end
                parser.on("--json", "JSON v1") { @opts[:json] = true }
            end

            def run(path)
                ledger = journal.ledger(path)
                snapshot = Snapshot.read(journal.db, ledger[:id])
                results = Checks.run(snapshot,
                                     final: @opts.fetch(:final, false))
                status = beat(ledger, status_line(snapshot))
                record_flags(snapshot)
                @opts[:json] ? json(results, status) : plain(results, status)
                results.all? { it[1] } ? 0 : 1
            end

            # A rule that passes with a detail warns: the line says so and
            # the exit status stays.
            def plain(results, status)
                results.each do |name, ok, detail|
                    @out.puts "#{mark(ok, detail)} #{name}#{detail_of(detail)}"
                    @out.puts "  hint: #{hint(name)}" if @opts[:hints] && !ok
                end
                @out.puts status
            end

            def mark(ok, detail)
                return "FAIL" unless ok

                detail.empty? ? "ok  " : "warn"
            end

            def detail_of(detail) = detail.empty? ? "" : " -- #{detail}"

            def hint(name)
                Checks::HINTS.fetch(name, "no hint for this report")
            end

            def json(results, status)
                reports = results.map do |name, ok, detail|
                    { name:, ok:, detail: }
                end
                schema = Render::Json::SCHEMA
                @out.puts JSON.generate(schema:, kind: "check", reports:,
                                        status:)
            end

            # The line, with `unchanged ×N` when it has not moved since the
            # last check; a peek is a read and counts nothing, and neither does
            # a check by a session other than the ledger's owner (or by none).
            def beat(ledger, line)
                return line if @opts[:peek]

                session = ENV.fetch("CLAUDE_CODE_SESSION_ID", "").strip
                owner = owner_of(ledger)
                return line if owner && owner != session

                count, text = Derive::StatusLine.beat(line, ledger[:beat_line],
                                                      ledger[:beat_count])
                store(ledger, line, count, owner && session)
                text
            end

            # The pieces' flags that moved since the last check, recorded
            # (FlagOutcomes); a peek is a read and records nothing.
            def record_flags(snapshot)
                return if @opts[:peek]

                derive = Derive.read(journal.db, snapshot)
                FlagOutcomes.new(journal.db, derive).record(err: @err)
            end

            def store(ledger, line, count, session)
                changes = { beat_line: line, beat_count: count }
                changes[:beat_session] = session if session
                journal.transaction do
                    journal.db[:ledgers].where(id: ledger[:id]).update(changes)
                end
            end

            # The session stored with the beat, else the session that wrote
            # the ledger's first event; nil when neither is a session.
            def owner_of(ledger)
                return ledger[:beat_session] if ledger[:beat_session]

                actor = journal.db[:events].where(ledger_id: ledger[:id])
                               .order(:id).get(:actor)
                return unless actor&.start_with?("session:")

                actor.delete_prefix("session:")
            end
        end
    end
end
