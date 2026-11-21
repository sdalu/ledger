# frozen_string_literal: true

require "ledger/after_action"
require "ledger/commands/answer"

module Ledger
    module Commands
        # `close PATH [--take N<n>...]`: a finished ledger leaves the live
        # ones, its row kept with `closed_at`; refused while `--final`
        # fails or an entry of the viewer is pending. `--take` files the
        # entries that asked for it (the viewer's Close) in the same event.
        # A close done prints its after-action block (AfterAction) first.
        class Close < CLI::Command
            include Taking

            USAGE = "PATH"
            SYNOPSIS = "PATH [--take N<n>...]"
            SUMMARY = "close a finished ledger; refused while check --final " \
                      "fails or an entry is pending"

            # The FAIL lines of a ledger not finished.
            class Unfinished < Error
                attr_reader :lines

                def initialize(lines)
                    super("not closed; --final fails")
                    @lines = lines
                end
            end

            private

            def flags(parser) = take_flag(parser)

            def run(path)
                id, noticed = closing(path)
                AfterAction.lines(journal.db, id).each { @out.puts it }
                @out.puts "closed: #{Address.parse(path)} (L#{id})"
                carry(noticed)
                0
            rescue Unfinished => e
                e.lines.each { @out.puts it }
                @err.puts "#{path}: #{e.message}"
                1
            end

            # The one write: the entries --take names taken, then the close.
            def closing(path)
                ids = takes
                write(path) do |change|
                    take(change, ids)
                    close(change)
                end.value
            end

            # -> [ledger id, noticed lines]; Unfinished when a rule fails.
            def close(change)
                snapshot = Snapshot.read(journal.db, change.ledger_id)
                failed = reports(snapshot).reject { it[1] }
                raise(Unfinished, failed.map { fail_line(*it) }) if failed.any?

                change.update(:ledgers, change.ledger_id, closed_at: Write.now)
                [change.ledger_id, noticed(snapshot)]
            end

            def noticed(snapshot) = snapshot.noticed.map { it[:line] }

            def reports(snapshot)
                waiting = snapshot.inbox_entries.reject { it[:taken_id] }
                                  .map { "N#{it[:n]}" }
                [*Checks.run(snapshot, final: true),
                 ["inbox", waiting.empty?,
                  "the user's entries not filed yet: #{waiting.join(", ")}"]]
            end

            def fail_line(name, _ok, detail)
                "FAIL #{name}#{" -- #{detail}" unless detail.empty?}"
            end

            def carry(lines)
                return if lines.empty?

                @out.puts "noticed, to carry: #{lines.size}"
                lines.each { @out.puts it }
            end
        end
    end
end
