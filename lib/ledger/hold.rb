# frozen_string_literal: true

module Ledger
    # A deliberate hold on a planned piece: the reason `piece --hold`
    # stored, which counts as cleared once every piece it names (P<n>)
    # is verified, kept, dropped or obsolete. A reason that names no
    # piece stays until it is cleared by hand; `piece --hold` refuses a
    # piece the ledger lacks, so a stored one names pieces that exist.
    module Hold
        # The statuses in which a piece named by a hold has settled.
        RELEASED = %w[verified kept dropped obsolete].freeze
        NAMED = /\bP([1-9]\d*)\b/

        # The reason still in force on PIECE, among PIECES (the ledger's
        # rows); nil when it has none, is not planned, or has been released.
        def self.active(piece, pieces)
            why = piece[:hold].to_s.strip
            return if why.empty? || piece[:status] != "planned"

            named = why.scan(NAMED).flatten.map(&:to_i)
            why unless released?(named, pieces)
        end

        def self.released?(named, pieces)
            return false if named.empty?

            status = pieces.to_h { [it[:n], it[:status]] }
            named.all? { RELEASED.include?(status[it]) }
        end
    end
end
