# frozen_string_literal: true

require "json"

module Ledger
    # The write path (docs/journal.md, section 2): one command, one
    # BEGIN IMMEDIATE transaction, one events row, every row change
    # recorded with its JSON before and after.
    #
    #     Ledger::Write.run(journal, address, "piece", argv) do |change|
    #         n = change.next_id("P")
    #         change.insert(:pieces, n:, status: "planned", ...)
    #     end
    #
    # Options: `own`, the visible id the command writes (a block that
    # gives the id sets it with `change.own =`); `dry`, roll back
    # after the block and the checks, keeping the result; `actor` and
    # `at` for the events row; `checks`, the rule runner of step 6, a
    # callable taking a Snapshot and answering [[rule, detail], ...]. The
    # write is refused (Worse) when after fails a rule before passed, or
    # a failure names `own` as a whole word: F1 never matches F10.
    class Write
        Result = Data.define(:event, :before, :after, :value, :dry)
        OPTIONS = { own: nil, dry: false, actor: nil, at: nil,
                    checks: nil }.freeze

        def self.now
            Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
        end

        # session:<id> when CLAUDE_CODE_SESSION_ID is set, else cli.
        def self.actor
            ENV["CLAUDE_CODE_SESSION_ID"]&.then { "session:#{it}" } || "cli"
        end

        def self.run(journal, address, command, argv, **, &)
            new(journal, address, command, argv, **).run(&)
        end

        def initialize(journal, address, command, argv, **options)
            unknown = options.keys - OPTIONS.keys
            raise ArgumentError, "unknown options: #{unknown}" if unknown.any?
            @journal = journal
            @address = address
            @command = command
            @argv = argv
            @options = OPTIONS.merge(options)
        end

        def run(&)
            result = nil
            @journal.transaction do
                result = write(&)
                raise Sequel::Rollback if dry?
            end
            result
        end

        private

        def db = @journal.db
        def dry? = @options.fetch(:dry)

        def write
            ledger = @journal.ledger(@address)
            before = Snapshot.read(db, ledger[:id])
            change = handle(ledger)
            value = yield change
            after = Snapshot.read(db, ledger[:id])
            refuse_worse(before, after, change.own)
            Result.new(event: finish_event(change), before:, after:, value:,
                       dry: dry?)
        end

        # The block's handle, its event inserted, `own` as the options give
        # it until the block names the id it writes.
        def handle(ledger)
            Change.new(db, ledger, insert_event(ledger[:id]),
                       own: @options[:own])
        end

        def insert_event(ledger_id)
            db[:events].insert(ledger_id:, at: @options[:at] || Write.now,
                               actor: @options[:actor] || Write.actor,
                               command: @command, argv: JSON.generate(@argv))
        end

        # The event row as committed, its summary the block's.
        def finish_event(change)
            event = db[:events].where(id: change.event_id)
            event.update(summary: change.summary) if change.summary
            event.first
        end

        def refuse_worse(before, after, own)
            checks = @options[:checks]
            return unless checks
            passed = checks.call(before).map(&:first)
            worse = checks.call(after).reject do |rule, detail|
                passed.include?(rule) && !names?(detail, own)
            end
            return if worse.empty?
            lines = worse.map { |rule, detail| "FAIL #{rule} -- #{detail}" }
            raise Worse, lines.join("\n")
        end

        # Whether DETAIL names OWN whole, no word character on either
        # side.
        def names?(detail, own)
            return false unless own

            whole = /(?<!\p{Word})#{Regexp.escape(own)}(?!\p{Word})/
            whole.match?(detail.to_s)
        end
    end

    # The block's handle on the write: every row change goes through it
    # and leaves an event_rows line; ids come from the counters.
    class Change
        # The table each visible id's letter names.
        TABLES = { "P" => :pieces, "O" => :questions, "D" => :criteria,
                   "C" => :constraints, "F" => :facts, "N" => :inbox_entries,
                   "X" => :decisions }.freeze
        # Columns filled from the write when the row leaves them out.
        WITH_LEDGER = (Snapshot::LEDGER_TABLES + [:pictures]).freeze
        WITH_EVENT = %i[links pictures piece_briefs piece_returns].freeze
        # The shape of a visible id.
        REF = /\A(?<kind>[PODCFNX])(?<n>[1-9]\d*)\z/

        attr_reader :ledger, :event_id
        # `own`: the visible id the command writes, set by the block once
        # its n is known.
        attr_accessor :summary, :own

        def initialize(db, ledger, event_id, own: nil)
            @db = db
            @ledger = ledger
            @event_id = event_id
            @own = own
        end

        def ledger_id = ledger[:id]

        # U3: the next n of a kind, inside the transaction; an id given
        # once is never given again, whatever became of its item.
        def next_id(kind)
            row = @db[:counters].where(ledger_id:, kind:).returning(:last)
                                .update(last: Sequel[:last] + 1).first
            raise Unknown, "no counter #{kind} for L#{ledger_id}" unless row
            row[:last]
        end

        def insert(table, **row)
            row[:ledger_id] = ledger_id if WITH_LEDGER.include?(table)
            row[:event_id] = event_id if WITH_EVENT.include?(table)
            id = @db[table].insert(row)
            record(table, id, nil, fetch(table, id))
            id
        end

        def update(table, id, **columns)
            before = fetch(table, id)
            @db[table].where(id:).update(columns)
            record(table, id, before, fetch(table, id))
        end

        def delete(table, id)
            before = fetch(table, id)
            @db[table].where(id:).delete
            record(table, id, before, nil)
        end

        # A visible id ("P7") to [table, row]; Unknown when it is not this
        # ledger's.
        def resolve(ref)
            match = REF.match(ref.to_s)
            raise Unknown, "#{ref} is not an id" unless match
            table = TABLES.fetch(match[:kind])
            row = @db[table].where(ledger_id:, n: match[:n].to_i).first
            raise Unknown, "#{ref} is not this ledger's" unless row
            [table, row]
        end

        # One edge, both ends resolved to rows inside the transaction.
        def link(kind, from, to)
            _, from_row = resolve(from)
            _, to_row = resolve(to)
            insert(:links, kind:, from_kind: from[0], from_row: from_row[:id],
                           to_kind: to[0], to_row: to_row[:id])
        end

        # U12: `out` stores the session and is refused under another
        # holder; any other status clears the claim.
        def status(piece_id, status, session: nil)
            if status == "out"
                claim(piece_id, session)
            else
                update(:pieces, piece_id, status:, claimed_by: nil)
            end
        end

        private

        def claim(piece_id, session)
            raise Refused, "--status out needs a session id" unless session
            piece = fetch(:pieces, piece_id)
            holder = piece[:claimed_by]
            if piece[:status] == "out" && holder && holder != session
                raise Claimed, "P#{piece[:n]} is out under #{holder} since " \
                               "#{claimed_at(piece_id, holder)}"
            end
            update(:pieces, piece_id, status: "out", claimed_by: session)
        end

        # The time of the event that gave the piece to its holder.
        def claimed_at(piece_id, holder)
            changes = @db[:event_rows].join(:events, id: :event_id)
                                      .where(tbl: "pieces", row_id: piece_id)
                                      .reverse(Sequel[:events][:id])
                                      .select_map(%i[at before after])
            at, = changes.find do |_, before, after|
                claimed_by(after) == holder && claimed_by(before) != holder
            end
            Time.at(at / 1000).strftime("%Y-%m-%d %H:%M:%S")
        end

        def claimed_by(json) = json && JSON.parse(json)["claimed_by"]

        def fetch(table, id) = @db[table].where(id:).first

        def record(table, id, before, after)
            return if table == :pictures
            @db[:event_rows].insert(event_id:, tbl: table.to_s, row_id: id,
                                    before: before&.to_json,
                                    after: after&.to_json)
        end
    end
end
