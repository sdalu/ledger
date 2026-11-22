# frozen_string_literal: true

require "ledger/derive"

module Ledger
    module Commands
        # What a landing frees: the started pieces (planned, awaiting no
        # word, not held) that come `after` the piece landed, once nothing
        # else holds them back, so that whoever recorded the landing is
        # told they can go out.
        class PieceReady
            # The refs, in row order, of the ready pieces that follow
            # piece P<n> in SNAPSHOT.
            def self.names(snapshot, n)
                derive = Derive.new(snapshot)
                derive.pieces.select { follows?(derive, it, n) }
                      .map { derive.ref(it) }
            end

            def self.follows?(derive, piece, n)
                derive.ready?(piece) && derive.after(piece).any? { it[:n] == n }
            end
        end
    end
end
