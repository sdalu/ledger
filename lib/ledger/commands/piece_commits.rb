# frozen_string_literal: true

module Ledger
    module Commands
        # `piece --commits SHA[,SHA...]`: the commits that landed a piece,
        # appended to the ones it holds, never replacing them. An id is 7 to
        # 40 hex digits, kept lower-case; one already held, or repeated in
        # the list, is ignored. Resolved inside the write, so a refusal
        # leaves nothing written.
        class PieceCommits
            SHA = /\A\h{7,40}\z/

            def initialize(change, db, opts)
                @change = change
                @db = db
                @opts = opts
            end

            # Appends the ids given to PIECE (a row id).
            def append(piece)
                return unless @opts.key?("commits")

                held = @db[:piece_commits].where(piece_id: piece)
                have = held.select_map(:sha)
                last = held.max(:position) || -1
                (listed - have).each_with_index do |sha, offset|
                    @change.insert(:piece_commits, piece_id: piece, sha:,
                                                   position: last + 1 + offset)
                end
            end

            private

            # The ids of the flag, lower-cased, each once, in order.
            def listed
                ids = @opts["commits"].split(/[,\s]+/).reject(&:empty?)
                raise Refused, "--commits takes SHA[,SHA...]" if ids.empty?

                ids.each do |id|
                    next if SHA.match?(id)

                    raise Refused, "--commits #{id}: 7 to 40 hex digits"
                end
                ids.map(&:downcase).uniq
            end
        end
    end
end
