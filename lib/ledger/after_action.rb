# frozen_string_literal: true

require "ledger/stats"

module Ledger
    # The after-action block `close` prints (docs/journal.md, section 4):
    # what one ledger's events say of its run, under `after action:`,
    # each line left out when it has nothing. The returns, the blocked
    # pieces and the spans out are those `stats` counts (Stats#tracks),
    # the asks read from the events still in force (Stats::InForce).
    # Nothing is written.
    #
    #     Ledger::AfterAction.lines(db, 3)
    #     # => ["after action:", "returned: P2 (depth)", "by me: X4"]
    class AfterAction
        HEADING = "after action:"
        EMPTY = "#{HEADING} nothing returned, blocked or stalled".freeze
        # A span out over an hour, no change of status, stalled.
        HOUR_MS = 3_600_000

        def self.lines(db, ledger_id) = new(db, ledger_id).lines

        def initialize(db, ledger_id)
            @db = db
            @ledger_id = ledger_id
            @tracks = Stats.new(db, [ledger_id]).tracks
                           .sort_by { it.piece[:n] }
        end

        # The heading and the lines with an item; the one line EMPTY
        # when none has.
        def lines
            body = [line("returned", returned), line("blocked", blocked),
                    line("stalled", stalled), line("answered", answered),
                    line("by me", by_me)].compact
            body.empty? ? [EMPTY] : [HEADING, *body]
        end

        private

        def line(label, items) = ("#{label}: #{items.join(", ")}" if items.any?)

        def piece(track) = "P#{track.piece[:n]}"

        # Each return, its cause from piece_returns or `unrecorded`.
        def returned
            @tracks.flat_map do |track|
                track.causes.map { "#{piece(track)} (#{it})" }
            end
        end

        def blocked = @tracks.select(&:blocked?).map { piece(it) }

        # The pieces with a span out over an hour, with the longest.
        def stalled
            @tracks.filter_map do |track|
                longest = track.spans.max
                next unless longest && longest > HOUR_MS

                "#{piece(track)} (#{duration(longest)})"
            end
        end

        # Each closed question: from the event that asked it to the event
        # of the decision that answers it, or the record not found.
        def answered
            reverted = Stats::InForce.new(@db, [@ledger_id]).reverted.to_a
            @db[:questions].where(ledger_id: @ledger_id).exclude(closed_at: nil)
                           .order(:n).all.map do |question|
                "O#{question[:n]} #{wait(question, reverted)}"
            end
        end

        def wait(question, reverted)
            asked = asked_at(question, reverted) or return "(no ask record)"
            answer = answered_at(question) or return "(no answer record)"
            duration(answer - asked)
        end

        # The time of the first event in force inserting QUESTION's row.
        def asked_at(question, reverted)
            @db[:event_rows].join(:events, id: :event_id)
                            .where(tbl: "questions", row_id: question[:id],
                                   before: nil, ledger_id: @ledger_id)
                            .exclude(event_id: reverted)
                            .order(:event_id).get(:at)
        end

        # The time of the event that wrote QUESTION's answers edge.
        def answered_at(question)
            links = Sequel[:links]
            @db[:links].join(:events, id: :event_id)
                       .where(links[:ledger_id] => @ledger_id,
                              kind: "answers", to_kind: "O",
                              to_row: question[:id])
                       .order(links[:id]).get(Sequel[:events][:at])
        end

        def by_me
            @db[:decisions].where(ledger_id: @ledger_id, by: "me").order(:n)
                           .select_map(:n).map { "X#{it}" }
        end

        # MS as `12 min` under an hour, else `2.1 h`.
        def duration(ms)
            minutes = ms.fdiv(60_000).round
            return "#{minutes} min" if minutes < 60

            format("%.1f h", ms.fdiv(HOUR_MS))
        end
    end
end
