# frozen_string_literal: true

require_relative "folder"
require_relative "text"

module LedgerViewer
    module Render
        # The tiles of a card's pictures: a thumbnail that opens in a
        # lightbox, a before/after pair as one, a short text figure
        # drawn in the card itself. Used by Mockups. A picture placed as a
        # directory is flagged, not drawn: which of its files is the one
        # to open is the picking rule's, not the viewer's.
        class Tiles
            TEXT_MAX = 64 * 1024
            TILE_LINES = 15
            THUMB_LINES = 12
            # `tile` is false for what stands loose in the card.
            Part = Data.define(:name, :html, :tile)

            # files: {name => [{path, type, size}]}; bytes: answers the
            # bytes of a picture of one file, by its name.
            def initialize(scope, lid, files, bytes)
                @scope = scope
                @lid = lid
                @files = files
                @bytes = bytes
            end

            # [the parts of the names drawn, the flags of the others].
            def parts(names)
                @real = names.to_h { [it, single(it)] }
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

            # The file a name is, or nil for a directory.
            def single(name)
                files = @files.fetch(name)
                files.first if files.length == 1 && files.first["path"].empty?
            end

            def absent(name)
                @scope.partial("ledger/mock_missing", name:)
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
                raw = @bytes.call(name)
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
