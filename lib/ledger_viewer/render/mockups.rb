# frozen_string_literal: true

require_relative "folder"
require_relative "terms"
require_relative "text"
require_relative "tiles"

module LedgerViewer
    module Render
        # The pictures an Open line names, or a flag for each one
        # missing: mockup_layout() of ledger-serve.py. Each name is one
        # Tiles::Part, a tile in the card's strip or a figure loose in it.
        class Mockups
            # statuses: {piece id => status}.
            def initialize(scope, lid, folder, statuses)
                @scope = scope
                @folder = folder
                @statuses = statuses
                @tiles = Tiles.new(scope, lid, folder)
            end

            # [the card's part, {item => the tiles for that item}]; an
            # item takes the tiles whose file starts with its code.
            def layout(text, items = [])
                names = text.scan(Text::MOCKUP_REF).flatten
                shown, missing = @tiles.parts(names)
                loose, inside = split(shown, items)
                [flags(text) + missing.join + lay(loose),
                 inside.transform_values { lay(it) }]
            end

            private

            def flags(text)
                text.scan(Text::PENDING).flatten.map { pending(it) }.join
            end

            def pending(id)
                status = @statuses.fetch(id, "missing")
                done = Terms.settled?(status)
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
