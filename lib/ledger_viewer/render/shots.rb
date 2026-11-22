# frozen_string_literal: true

require_relative "tiles"

module LedgerViewer
    module Render
        # The picture of one option of a question: a thumbnail tile that
        # opens like any mockup, drawn inside the option's own tile; a
        # short text picture is a tile too, for the option's tile has no
        # room to draw it in full.
        class Shots < Tiles
            # The html of the picture NAME.
            def shot(name)
                return absent(name) unless single(name)
                return text_shot(name) if kind(name) == "text"

                part = tile(name, button(name, kind(name),
                                         thumb(url(name), kind(name), name)),
                            "")
                part.html
            end

            private

            def text_shot(name)
                body, cut, lines = text_of(name)
                text_tile(name, body, cut, lines).html
            end
        end
    end
end
