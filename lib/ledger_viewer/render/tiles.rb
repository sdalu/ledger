# frozen_string_literal: true

require_relative "folder"
require_relative "text"
require_relative "text_tiles"

module LedgerViewer
    module Render
        # The tiles of a card's pictures: a thumbnail that opens in a
        # lightbox, a before/after pair as one, a short text figure
        # drawn in the card itself. Used by Mockups. A picture placed as a
        # directory is drawn by the file Ledger::Pictures.pick names, its
        # other files served under it; one that picks none is flagged.
        class Tiles
            include TextTiles

            # `tile` is false for what stands loose in the card.
            Part = Data.define(:name, :html, :tile)

            # base: the path the ledger's files are under ("/m/k/TOKEN/LID");
            # files: {name => [{path, type, size}]}; bytes: answers the
            # bytes of a picture of one file, by its name.
            def initialize(scope, base, files, bytes)
                @scope = scope
                @base = base
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

            # The file a name is drawn by, or nil for a directory that
            # picks none.
            def single(name) = Folder.drawn(@files.fetch(name))

            # The path a name is served by: the name, or its picked file.
            def target(name) = Folder.target(name, single(name))

            def kind(name) = Folder.kind(target(name))

            def absent(name)
                @scope.partial("ledger/mock_missing", name:)
            end

            def url(name) = "#{@base}/#{Text.quote(target(name))}"

            def part(name)
                return pair(name) if @pairs.key?(name)
                kind = kind(name)
                return text(name) if kind == "text"

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
            def pair(name) = sides(@pairs.fetch(name), name, name)

            # BEFORE and AFTER, one tile with a side each, under LABEL.
            def sides(before, after, label)
                sides = [["Before", before], ["After", after]].map do |word, n|
                    side(label, n, word)
                end
                html = @scope.partial(
                    "ledger/mock_pair",
                    { sides:, label:, before: url(before), after: url(after) }
                )
                Part.new(label, html, true)
            end

            def side(label, name, word)
                @scope.partial("ledger/mock_side",
                               button: side_button(label, name, word))
            end

            # NAME's thumbnail under WORD (Before or After).
            def side_button(label, name, word)
                text = "#{label} (#{word.downcase})"
                kind = kind(name)
                inner = thumb(url(name), kind, text) +
                        %(<span class="side-name">#{word}</span>)
                button(name, kind, inner, text)
            end
        end
    end
end
