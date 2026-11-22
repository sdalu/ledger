# frozen_string_literal: true

require "ledger/abandon"
require "ledger/after_action"
require "ledger/commands/answer"

module Ledger
    module Commands
        # `close PATH [--abandon] [--take N<n>...]`: a ledger leaves the
        # live ones, its row kept with `closed_at`; refused while an entry
        # of the viewer is pending, and while `--final` fails unless it is
        # abandoned (Abandon: its open pieces dropped, its open questions
        # closed, in the same event). `--take` files the entries that
        # asked for it (the viewer's Close or Abandon) in the same event.
        # A close done prints its after-action block (AfterAction) first,
        # the block its event keeps as summary.
        class Close < CLI::Command
            include Taking

            USAGE = "PATH"
            SYNOPSIS = "PATH [--abandon] [--take N<n>...]"
            SUMMARY = "close a finished ledger, or abandon an unfinished " \
                      "one; refused while check --final fails (unless " \
                      "--abandon) or an entry is pending"

            # The FAIL lines of a ledger not closed.
            class Unfinished < Error
                attr_reader :lines

                def initialize(lines, message)
                    super(message)
                    @lines = lines
                end
            end

            private

            def flags(parser)
                parser.on(Abandon::FLAG, "close it unfinished: open pieces " \
                                         "dropped, open questions closed") do
                    @opts[:abandon] = true
                end
                take_flag(parser)
            end

            def abandon? = @opts.fetch(:abandon, false)

            def run(path)
                id, noticed = closed(path)
                done = abandon? ? "abandoned" : "closed"
                @out.puts "#{done}: #{Address.parse(path)} (L#{id})"
                carry(noticed)
                0
            rescue Unfinished => e
                unfinished(path, e)
            end

            # The finish gate's refusal printed and recorded (each FAIL
            # line a refusal `final`); exit 1.
            def unfinished(path, error)
                error.lines.each { @out.puts it }
                @err.puts "#{path}: #{error.message}"
                RefusalOutcomes.new(@words, err: @err).final(error.lines)
                1
            end

            # The close written, its after-action block printed; -> the
            # write's value.
            def closed(path)
                result = closing(path)
                @out.puts result.event[:summary]
                result.value
            end

            # The one write: the entries --take names taken, an abandon's
            # drops and decisions, then the close, its after-action block
            # (AfterAction) stored as the event's summary.
            def closing(path)
                ids = takes
                write(path) do |change|
                    take(change, ids)
                    Abandon.write(change, journal.db) if abandon?
                    close(change).tap do
                        change.summary = AfterAction.lines(journal.db,
                                                           change.ledger_id)
                                                    .join("\n")
                    end
                end
            end

            # -> [ledger id, noticed lines]; Unfinished when a rule fails.
            def close(change)
                snapshot = Snapshot.read(journal.db, change.ledger_id)
                passes!(snapshot)
                change.update(:ledgers, change.ledger_id, closed_at: Write.now)
                [change.ledger_id, noticed(snapshot)]
            end

            def passes!(snapshot)
                failed = reports(snapshot).reject { it[1] }
                return if failed.empty?

                raise Unfinished.new(failed.map { fail_line(*it) }, refusal)
            end

            def refusal
                return "not closed; --final fails" unless abandon?

                "not abandoned; an entry is pending"
            end

            def noticed(snapshot) = snapshot.noticed.map { it[:line] }

            # The rules a close passes; an abandon passes the inbox's alone.
            def reports(snapshot)
                waiting = snapshot.inbox_entries.reject { it[:taken_id] }
                                  .map { "N#{it[:n]}" }
                inbox = ["inbox", waiting.empty?,
                         "the user's entries not filed yet: " \
                         "#{waiting.join(", ")}"]
                return [inbox] if abandon?

                [*Checks.run(snapshot, final: true), inbox]
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
