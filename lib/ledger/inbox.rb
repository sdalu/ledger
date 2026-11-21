# frozen_string_literal: true

require "json"

require "ledger/hooks/entry"

module Ledger
    # The user's channel to a session (docs/journal.md, sections 2 and 4):
    # entries the viewer sends, numbered N<n> in the write transaction,
    # shown as `inbox` prints them, taken by a session when filed.
    #
    #     ids = Ledger::Inbox.append(journal, address,
    #                                [{ "ref" => "O3", "text" => "warm" }],
    #                                actor: "viewer:anna")
    #
    # Each entry's hash holds the viewer's fields (`ref`, `word`,
    # `choice`, `order`, `notes`, `picks`, `replaces`, `comment`: true on
    # a comment on a question, no answer, `picture`: the kind of picture
    # asked on a question or a piece) and `text`. One
    # call is one `inbox` event, however many entries it files.
    module Inbox
        STAMP = "%Y-%m-%d %H:%M:%S"
        # What an entry is about: a question, a piece, the order, or the
        # ledger itself (close, abandon).
        REF = /\A(?:order|close|abandon|[OP][1-9]\d*)\z/
        REFS = "O<n>, P<n>, order, close or abandon"
        # Fields the journal gives, never the caller.
        GIVEN = %w[id at].freeze

        # Seconds between two looks of `inbox --wait` and `--follow`.
        class << self
            attr_accessor :poll
        end
        self.poll = 1.0

        # The ids ("N4") given to ENTRIES, filed in one event under
        # ACTOR. Every entry is checked before any is written; the ledger
        # is not checked, an entry is the user's words, not a change to
        # its items.
        def self.append(journal, address, entries, actor:, now: Time.now)
            fields = entries.map { fields(it) }
            raise Refused, "no entry to send" if fields.empty?

            write = Write.run(journal, address, "inbox", [], actor:) do |change|
                ids = fields.map { insert(change, it, now) }
                change.summary = ids.join(", ")
                ids
            end
            write.value
        end

        def self.fields(entry)
            fields = entry.transform_keys(&:to_s)
            given = GIVEN & fields.keys
            raise Refused, "an entry's #{given.first} is the journal's" if
                given.any?
            raise Refused, "an entry needs its text" unless
                fields["text"].is_a?(String)
            ref = fields["ref"]
            return fields if ref.nil? || REF.match?(ref.to_s)

            raise Refused, "ref is #{REFS}, not #{ref.inspect}"
        end

        def self.insert(change, fields, now)
            n = change.next_id("N")
            at = now.strftime(STAMP)
            body = { "id" => "N#{n}", "at" => at,
                     **fields.except("text"), "text" => fields["text"] }
            change.insert(:inbox_entries, n:, at:, ref: fields["ref"]&.to_s,
                                          payload: JSON.generate(body),
                                          malformed: false)
            "N#{n}"
        end

        # The entry's rows no take has recorded, in order.
        def self.pending(snapshot)
            snapshot.inbox_entries.reject { it[:taken_id] }
        end

        # One entry as `ledger inbox` prints it: a malformed line is
        # shown whole, never dropped.
        def self.show(row)
            return Hooks::Entry.show(row) unless row[:malformed]

            lines = row[:payload].split("\n", -1).map { "    #{it}" }
            "N#{row[:n]} (?, malformed line):\n#{lines.join("\n")}"
        end

        # `inbox --wait` and `--follow`: read only. The ledger's newest event
        # id is looked at every POLL seconds, and the entries are read again
        # only when it moved (an entry and a take are both events). Waiting
        # prints the pending entries once there are any and answers 0, or 1
        # at the timeout. Following holds each new entry and prints the held
        # ones together once none has arrived for QUIET seconds (0 prints
        # each at once); the burst still held when it is stopped is printed
        # before it ends, and an entry taken meanwhile is not printed.
        class Watch
            MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
            DEFAULTS = { follow: false, timeout: nil, quiet: 60.0, poll: nil,
                         clock: MONOTONIC,
                         sleeper: Kernel.method(:sleep) }.freeze

            # Options: `follow`, `timeout` (seconds, nil: none), `quiet`,
            # `poll` (Inbox.poll by default), and `clock` and `sleeper`, which
            # a test replaces.
            def initialize(journal, ledger_id, out, **options)
                unknown = options.keys - DEFAULTS.keys
                raise ArgumentError, "unknown: #{unknown}" if unknown.any?

                @db = journal.db
                @ledger_id = ledger_id
                @out = out
                @options = DEFAULTS.merge(options)
                @shown = []
                @held = []
                @newest = :unset
            end

            def call
                deadline = @options[:timeout]&.then { now + it }
                loop do
                    status = step(deadline) and return status

                    @options[:sleeper].call(@options[:poll] || Inbox.poll)
                end
            ensure
                release if @options[:follow] && @held.any?
            end

            private

            # 0 once entries were printed, 1 at the deadline, else nil.
            def step(deadline)
                return 0 if scan

                release if @held.any? && now - @arrived >= @options[:quiet]
                1 if deadline && now >= deadline
            end

            def now = @options[:clock].call

            # Whether the entries were printed (waiting); following holds them.
            def scan
                newest = @db[:events].where(ledger_id: @ledger_id).max(:id)
                return false if newest == @newest

                @newest = newest
                fresh = pending.reject { @shown.include?(it[:id]) }
                return false if fresh.empty?
                return print_all(fresh) unless @options[:follow]

                @shown.concat(fresh.map { it[:id] })
                @held.concat(fresh)
                @arrived = now
                false
            end

            def pending
                @db[:inbox_entries].where(ledger_id: @ledger_id, taken_id: nil)
                                   .order(:id).all
            end

            def print_all(rows)
                @out.puts rows.map { Inbox.show(it) }.join("\n")
                @out.flush if @out.respond_to?(:flush)
                true
            rescue Errno::EPIPE
                true
            end

            def release
                free = pending.map { it[:id] }
                rows = @held.select { free.include?(it[:id]) }
                print_all(rows) if rows.any?
            ensure
                @held.clear
            end
        end
    end
end
