# frozen_string_literal: true

module LedgerViewer
    module Render
        # What the parts of one ledger page are built from: the page's
        # scope, the reading of the ledger, and the builders that draw
        # its forms, cases, references, pictures and Markdown.
        Kit = Data.define(:scope, :reading, :lid, :say, :word, :cases,
                          :refs, :mockups, :blocks)
    end
end
