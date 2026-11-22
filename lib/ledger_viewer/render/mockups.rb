# frozen_string_literal: true

require_relative "text"
require_relative "piece_tiles"

module LedgerViewer
    module Render
        # The pictures a question names, and a flag for each one still
        # pending. Each name is one Tiles::Part, a tile in the card's
        # strip or a figure loose in it. And a piece's before/after.
        class Mockups
            # reading: the ledger's Reading; bytes: answers the bytes of
            # the picture of one file a name is.
            def initialize(scope, base, reading, bytes)
                @scope = scope
                @reading = reading
                @tiles = PieceTiles.new(scope, base, files(reading), bytes)
            end

            # [the card's part, {item => the tiles for that item}] of a
            # question's `pictures`; an item takes the tiles whose file
            # starts with its code.
            def layout(pictures, items = [])
                names = pictures.filter_map { it["name"] }
                shown, missing = @tiles.parts(names)
                loose, inside = split(shown, items)
                [flags(pictures) + missing.join + lay(loose),
                 inside.transform_values { lay(it) }]
            end

            # A piece's before/after, drawn side by side, and its reason
            # for none, a muted line; "" when it has neither.
            def sides(piece)
                names = piece.fetch("pictures", [])
                             .to_h { [it["role"], it["name"]] }
                why = piece["no_picture"].to_s
                reason = %(<p class="no-picture">no picture: ) \
                         "#{Text.escape(why)}</p>"
                "#{pair(piece, names)}#{reason unless why.empty?}"
            end

            # The before/after tile in a strip of its own.
            def pair(piece, names)
                return "" if names.empty?

                tile = @tiles.roles(names, "#{piece["id"]} before/after")
                %(<div class="mock-strip">#{tile.html}</div>)
            end

            private

            # {name => its files} of the ledger's pictures.
            def files(reading)
                reading.pictures.to_h { [it["name"], it["files"]] }
            end

            def flags(pictures)
                pictures.filter_map { it["pending"] }.map { pending(it) }.join
            end

            def pending(id)
                status = @reading.statuses.fetch(id)
                done = @reading.settled.fetch(id)
                @scope.partial("ledger/mock_pending", { id:, status:, done: })
            end

            def split(shown, items)
                codes = items.to_h { [it, "#{Text.words(it).first}-".downcase] }
                inside = Hash.new { |hash, key| hash[key] = [] }
                loose = shown.reject do |part|
                    item = owner(part, codes) or next false
                    inside[item] << part
                end
                [loose, inside]
            end

            # The item whose code the file's name starts with.
            def owner(part, codes)
                base = part.name.rpartition("/").last.downcase
                codes.find { |_, code| code != "-" && base.start_with?(code) }
                     &.first
            end

            def lay(parts)
                loose = parts.reject(&:tile).map(&:html).join
                tiles = parts.select(&:tile).map(&:html).join
                return loose if tiles.empty?

                %(#{loose}<div class="mock-strip">#{tiles}</div>)
            end
        end
    end
end
