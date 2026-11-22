# frozen_string_literal: true

require "json"

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

            # The line, with `unchanged xN` when it has not moved since the
            # last check; a peek is a read and counts nothing.
            def beat(ledger, line)
                return line if @opts[:peek]

                count, text = Derive::StatusLine.beat(line, ledger[:beat_line],
                                                      ledger[:beat_count])
                journal.transaction do
                    journal.db[:ledgers].where(id: ledger[:id])
                           .update(beat_line: line, beat_count: count)
                end
                text
            end
        end
    end
end
