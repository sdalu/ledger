# frozen_string_literal: true

require_relative "tiles"

module LedgerViewer
    module Render
        # The tiles of a card, and a piece's before/after: the pair as one
        # tile of two sides, before left; a side placed alone as a tile
        # of its own, under its word.
        class PieceTiles < Tiles
            # {"before" => name, "after" => name}, a side perhaps missing,
            # as one tile under LABEL.
            def roles(names, label)
                before, after = names.values_at("before", "after")
                return sides(before, after, label) if before && after

                name = before || after
                button = side_button(label, name, before ? "Before" : "After")
                tile(name, button, "")
            end
        end
    end
end
