# frozen_string_literal: true

module Ledger
    class Stats
        # What came of the dispatches announced (`piece --announce`), by
        # the highest axis the assessment named and by its model. A
        # group counts its piece_assessments rows (dispatches); the
        # pieces whose first dispatch it holds, and of those the ones
        # verified with no return (Track#first_pass?); and each return
        # by cause, laid on the piece's last dispatch before it (a
        # return before any dispatch counts nowhere).
        #
        #     Stats::Assessments.new(db, [3], stats.tracks).by_axis
        #     # => [#<data Group label="stakes", dispatches=2, ...>]
        class Assessments
            Group = Data.define(:label, :dispatches, :pieces, :first_time,
                                :returns)

            def initialize(db, ledger_ids, tracks)
                @rows = db[:piece_assessments].where(ledger_id: ledger_ids)
                                              .order(:event_id, :id).all
                @tracks = tracks.to_h { [it.piece[:id], it] }
                @firsts = @rows.group_by { it[:piece_id] }
                               .transform_values(&:first)
            end

            def any? = @rows.any?

            # By highest axis, by name; the rows naming none last, their
            # label nil.
            def by_axis
                groups { it[:axis] }
                    .sort_by { [it.label ? 0 : 1, it.label.to_s] }
            end

            # By model: haiku to fable, then any other name by name.
            def by_model
                groups { it[:model] }.sort_by do |group|
                    [MODELS.index(group.label) || MODELS.size, group.label]
                end
            end

            private

            def groups(&)
                @rows.group_by(&).map { |label, rows| group(label, rows) }
            end

            def group(label, rows)
                firsts = rows.select { @firsts[it[:piece_id]].equal?(it) }
                Group.new(label:, dispatches: rows.size, pieces: firsts.size,
                          first_time: firsts.count { first_pass?(it) },
                          returns: Stats.tally(rows.flat_map { returns(it) }))
            end

            def first_pass?(row) = @tracks[row[:piece_id]]&.first_pass?

            # The causes of the returns that ROW was the last dispatch
            # before.
            def returns(row)
                track = @tracks[row[:piece_id]] or return []

                track.caused.filter_map do |event_id, cause|
                    cause if last_before(row[:piece_id], event_id).equal?(row)
                end
            end

            def last_before(piece_id, event_id)
                @rows.select do |row|
                    row[:piece_id] == piece_id && row[:event_id] < event_id
                end.last
            end
        end
    end
end
