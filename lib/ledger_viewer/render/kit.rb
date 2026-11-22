# frozen_string_literal: true

module LedgerViewer
    module Render
        # What the parts of one ledger page are built from: the page's
        # scope, the reading of the ledger, and the builders that draw
        # its forms, cases, references, pictures and Markdown, the fold
        # that asks for a picture, and the RAID line of each piece and
        # question, and the ties of each piece.
        Kit = Data.define(:scope, :reading, :lid, :say, :word, :picture,
                          :cases, :refs, :mockups, :blocks, :raid, :ties)
    end
end
