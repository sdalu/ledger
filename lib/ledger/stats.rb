# frozen_string_literal: true

require "json"

require "ledger/derive"
require "ledger/snapshot"

module Ledger
    # A track record per route (docs/journal.md, section 4, `stats`): the
    # pieces of the ledgers named, grouped by the route each has now, and
    # what their history says. The status changes are read from
    # event_rows, so a return written before piece_returns existed still
    # counts, as `unrecorded`; only the events still in force count
    # (Stats::InForce). Nothing is written.
    #
    #     Ledger::Stats.read(db, [3, 4]).map(&:route)
    #     # => ["sonnet, effort: medium", "peer: web", "kept"]
    class Stats
        MODELS = %w[haiku sonnet opus fable].freeze
        EFFORTS = %w[low medium high xhigh max].freeze
        # The cause of a return with no piece_returns row.
        UNRECORDED = "unrecorded"

        # One group: its route, its pieces, those verified and those
        # verified without a return, those ever blocked, those ready and
        # unsent now (Derive#unsent), the median span out in ms (nil
        # without one) and the returns {cause => count}.
        Group = Data.define(:route, :pieces, :verified, :first_pass,
                            :blocked, :unsent, :median_out_ms,
                            :returns) do
            # Of the pieces verified, the share never returned; nil when
            # none is verified.
            def first_pass_share
                first_pass.fdiv(verified) unless verified.zero?
            end

            def blocked_share = blocked.fdiv(pieces)
            def median_out_minutes = median_out_ms&.fdiv(60_000)
        end

        # A change of a piece's status by one event; FROM is nil for an
        # insert, TO nil for a delete.
        Change = Data.define(:piece_id, :event_id, :at, :from, :to)

        def self.read(db, ledger_ids, **) = new(db, ledger_ids, **).groups

        # NOW (ms) dates the pieces unsent.
        def initialize(db, ledger_ids, now: Write.now)
            @db = db
            @now = now
            @pieces = db[:pieces].where(ledger_id: ledger_ids).all
            @reverted = InForce.new(db, ledger_ids).reverted
            @changes = changes.group_by(&:piece_id)
            @recorded = db[:piece_returns].where(piece_id: ids)
                                          .select_map(%i[piece_id event_id
                                                         cause])
                                          .group_by(&:first)
        end

        # The groups: model routes by model then effort, then the peers,
        # then kept.
        def groups
            @pieces.group_by { [rank(it), route(it)] }.sort_by(&:first)
                   .map { |(_, label), list| group(label, list) }
        end

        # Each piece read through its history, a Track (`close` reads one
        # ledger this way for its after-action block).
        def tracks = @pieces.map { track(it) }

        private

        def ids = @pieces.map { it[:id] }

        def route(piece)
            return "kept" if piece[:status] == "kept"
            return "peer: #{piece[:peer]}" if piece[:peer]

            "#{piece[:model]}, effort: #{piece[:effort]}"
        end

        def rank(piece)
            return [2] if piece[:status] == "kept"
            return [1] if piece[:peer]

            [0, MODELS.index(piece[:model]), EFFORTS.index(piece[:effort])]
        end

        def group(label, pieces)
            tracks = pieces.map { track(it) }
            verified = tracks.select(&:verified?)
            Group.new(route: label, pieces: tracks.size,
                      verified: verified.size,
                      first_pass: verified.count(&:first_pass?),
                      blocked: tracks.count(&:blocked?),
                      unsent: pieces.count { unsent.include?(it[:id]) },
                      median_out_ms: median(tracks.flat_map(&:spans)),
                      returns: tally(tracks.flat_map(&:causes)))
        end

        def track(piece)
            Track.new(piece, @changes.fetch(piece[:id], []),
                      @recorded.fetch(piece[:id], []))
        end

        # The ids of the pieces unsent, over the live ledgers of the
        # pieces: a closed one has no piece planned.
        def unsent
            ledgers = @pieces.map { it[:ledger_id] }.uniq
            @unsent ||= @db[:ledgers].where(id: ledgers, closed_at: nil)
                                     .select_map(:id).flat_map do |id|
                derive = Derive.read(@db, Snapshot.read(@db, id), now: @now)
                derive.unsent.map { it.first[:id] }
            end
        end

        def median(values)
            return if values.empty?

            sorted = values.sort
            middle = sorted.size / 2
            return sorted[middle] if sorted.size.odd?

            (sorted[middle - 1] + sorted[middle]).fdiv(2)
        end

        # The causes counted, the named ones by name, unrecorded last.
        def tally(causes)
            causes.tally.sort_by do |cause, _|
                [cause == UNRECORDED ? 1 : 0, cause]
            end.to_h
        end

        # The status changes of the pieces, oldest first: event_rows on
        # pieces from events of the piece's own ledger still in force.
        def changes
            ledgers = @pieces.to_h { [it[:id], it[:ledger_id]] }
            @db[:event_rows].join(:events, id: :event_id)
                            .where(tbl: "pieces", row_id: ledgers.keys)
                            .order(:event_id, Sequel[:event_rows][:rowid])
                            .select(:row_id, :event_id, :before, :after,
                                    :ledger_id, :at)
                            .filter_map do |row|
                change(row) if in_force?(row, ledgers)
            end
        end

        # Whether ROW is of its piece's own ledger and of an event in force.
        def in_force?(row, ledgers)
            ledgers[row[:row_id]] == row[:ledger_id] &&
                !@reverted.include?(row[:event_id])
        end

        def change(row)
            from, to = row.values_at(:before, :after).map { status(it) }
            return if from == to

            Change.new(piece_id: row[:row_id], event_id: row[:event_id],
                       at: row[:at], from:, to:)
        end

        def status(json) = json && JSON.parse(json)["status"]
    end
end

require "ledger/stats/in_force"
require "ledger/stats/track"
