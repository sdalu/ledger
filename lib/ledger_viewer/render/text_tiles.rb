# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # The tiles of a text picture (`.txt`, a figure): a short one is
        # drawn in the card itself, a longer one is a thumbnail tile that
        # opens in full. Mixed into Tiles, whose tile, button, url and
        # thumb it draws with.
        module TextTiles
            TEXT_MAX = 64 * 1024
            TILE_LINES = 15
            THUMB_LINES = 12

            private

            def text(name)
                body, cut, lines = text_of(name)
                return figure(name, body, cut) if lines.length <= TILE_LINES

                text_tile(name, body, cut, lines)
            end

            # [body, cut, lines] of a text picture, cut at TEXT_MAX.
            def text_of(name)
                raw = @bytes.call(name)
                body = raw.byteslice(0, TEXT_MAX).force_encoding("UTF-8")
                          .scrub("�")
                [body, raw.bytesize > TEXT_MAX, Text.splitlines(body)]
            end

            def text_tile(name, body, cut, lines)
                inner = thumb_text(lines.first(THUMB_LINES))
                full = @scope.partial("ledger/mock_full", body:, cut:)
                tile(name, button(name, "text", inner), full)
            end

            def thumb_text(lines)
                @scope.partial("ledger/mock_thumb_text", text: lines.join("\n"))
            end

            # A short text figure is drawn in the card itself.
            def figure(name, body, cut)
                attrs, box = @scope.tip(
                    "Open it beside the page (over it on a narrow screen)"
                )
                html = @scope.partial(
                    "ledger/mock_figure",
                    { body:, cut:, label: name, url: url(name), attrs:, box: }
                )
                Tiles::Part.new(name, html, false)
            end
        end
    end
end
