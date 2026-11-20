# frozen_string_literal: true

require_relative "folder"
require_relative "text"

module LedgerViewer
    module Render
        # The tiles of a card's pictures: a thumbnail that opens in a
        # lightbox, a before/after pair as one, a short text figure
        # drawn in the card itself. Used by Mockups.
        class Tiles
            TEXT_MAX = 64 * 1024
            TILE_LINES = 15
            THUMB_LINES = 12
            # `tile` is false for what stands loose in the card.
            Part = Data.define(:name, :html, :tile)

            def initialize(scope, lid, folder)
                @scope = scope
                @lid = lid
                @folder = folder
            end

            # [the parts of the names that exist, the flags of the ones
            # that do not].
            def parts(names)
                @real = names.to_h { [it, Folder.file(@folder, it)] }
                @pairs = Folder.pairs(names, @real)
                before = @pairs.values
                shown = []
                missing = []
                names.each do |name|
                    next missing << absent(name) unless @real[name]

                    shown << part(name) unless before.include?(name)
                end
                [shown.compact, missing]
            end

            private

            def absent(name)
                @scope.partial("ledger/mock_missing", name:, folder: @folder)
            end

            def url(name) = "/m/#{@lid}/#{Text.quote(name)}"

            def part(name)
                return pair(name) if @pairs.key?(name)
                return text(name) if Folder.kind(name) == "text"

                kind = Folder.kind(name)
                inner = thumb(url(name), kind, name)
                tile(name, button(name, kind, inner), "")
            end

            def button(name, kind, inner, label = name)
                @scope.partial("ledger/mock_button", url: url(name), kind:,
                                                     label:, inner:)
            end

            def thumb(url, kind, label)
                @scope.partial("ledger/mock_thumb", url:, kind:, label:)
            end

            def tile(name, button, full)
                html = @scope.partial(
                    "ledger/mock_tile",
                    { button:, full:, label: name, url: url(name) }
                )
                Part.new(name, html, true)
            end

            # `before-X` and its after, one tile with a side each.
            def pair(name)
                before = @pairs.fetch(name)
                sides = [["Before", before], ["After", name]].map do |word, n|
                    side(name, n, word)
                end
                html = @scope.partial(
                    "ledger/mock_pair",
                    { sides:, label: name, before: url(before),
                      after: url(name) }
                )
                Part.new(name, html, true)
            end

            def side(label, name, word)
                text = "#{label} (#{word.downcase})"
                kind = Folder.kind(name)
                inner = thumb(url(name), kind, text) +
                        %(<span class="side-name">#{word}</span>)
                @scope.partial("ledger/mock_side",
                               button: button(name, kind, inner, text))
            end

            def text(name)
                raw = File.binread(@real[name], TEXT_MAX + 1)
                cut = raw.bytesize > TEXT_MAX
                body = raw.byteslice(0, TEXT_MAX).force_encoding("UTF-8")
                          .scrub("�")
                lines = Text.splitlines(body)
                return figure(name, body, cut) if lines.length <= TILE_LINES

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
                Part.new(name, html, false)
            end
        end
    end
end
