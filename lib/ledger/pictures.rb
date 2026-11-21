# frozen_string_literal: true

require "find"

module Ledger
    # A mockup's files as the journal keeps them (docs/journal.md, S1):
    # one `pictures` row per file, the bytes as they are on disk, nothing
    # written back to a disk. A file placed alone is a name with path ""; a
    # directory is one name (its own) with a row per file, `path` the
    # file's place under it.
    module Pictures
        TYPES = { ".html" => "text/html; charset=utf-8",
                  ".htm" => "text/html; charset=utf-8",
                  ".css" => "text/css; charset=utf-8",
                  ".js" => "text/javascript; charset=utf-8",
                  ".json" => "application/json",
                  ".txt" => "text/plain; charset=utf-8",
                  ".svg" => "image/svg+xml", ".png" => "image/png",
                  ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg",
                  ".gif" => "image/gif", ".webp" => "image/webp",
                  ".woff" => "font/woff", ".woff2" => "font/woff2",
                  ".ttf" => "font/ttf" }.freeze
        # What a name opens on, in this order of preference.
        CLASSES = [%w[.html .htm], %w[.svg .png .jpg .jpeg .gif .webp],
                   %w[.txt]].freeze
        # A piece of a name a line's `mockup: NAME` can spell.
        PART = /\A[\w.-]+\z/

        # One file to store: its NAME, its PATH under a directory (""
        # alone), the served TYPE and its BYTES.
        Item = Data.define(:name, :path, :type, :bytes) do
            def file = path.empty? ? name : "#{name}/#{path}"
            def extension = File.extname(path.empty? ? name : path).downcase
        end

        # The one file a name opens on: the only page, else the only image,
        # else the only text; nil when there is none or several. Over the
        # rows of one name, or over every file a mockup placed.
        def self.page(items)
            group = CLASSES.lazy.map { |kinds| of_kinds(items, kinds) }
                           .find(&:any?)
            group.first if group&.one?
        end

        def self.of_kinds(items, kinds)
            items.select { kinds.include?(it.extension) }
        end

        # The file a directory is drawn by, among PATHS (its files, under
        # it): index.html at its top, else its single page, else its
        # single image or SVG; nil when there is none or several. The
        # first kind present decides, so two pages and an image are
        # several, not the image. The command and the viewer both ask.
        def self.pick(paths)
            return "index.html" if paths.include?("index.html")

            group = CLASSES.first(2).lazy.map do |kinds|
                paths.select { kinds.include?(File.extname(it).downcase) }
            end.find(&:any?)
            group.first if group&.one?
        end

        # [[name, the file it opens on]] of every name among ITEMS, in
        # their order; a name that opens on nothing is refused.
        def self.shown(items)
            items.group_by(&:name).map do |name, rows|
                [name, opens(name, rows)]
            end
        end

        def self.opens(name, rows)
            if rows.one? && rows.first.path.empty?
                return name if page(rows)

                raise Refused, "no single page, image or text to pick in " \
                               "#{name}"
            end
            path = pick(rows.map(&:path)) or
                raise(Refused, "no index.html, single page or single " \
                               "image to pick in #{name}")
            "#{name}/#{path}"
        end

        # The files at SOURCES (a file, or a directory with everything
        # under it) as items, refused before anything is stored.
        class Sources
            def initialize(sources)
                @sources = sources
            end

            def items
                list = @sources.flat_map { entry(it) }
                refuse("nothing to place") if list.empty?
                twice = list.map(&:file).tally.reject { |_, n| n == 1 }.keys
                refuse("#{twice.join(", ")}: placed twice") if twice.any?
                list
            end

            private

            def refuse(message) = raise(Refused, message)

            def entry(source)
                refuse("#{source}: a symlink; copy the file itself") if
                    File.symlink?(source)
                return [item(File.basename(source), "", source)] if
                    File.file?(source)
                return directory(source) if File.directory?(source)

                refuse("#{source}: no such file or directory")
            end

            def directory(source)
                name = File.basename(File.expand_path(source))
                found = Find.find(source).reject { it == source }.sort
                found.each do |file|
                    refuse("#{file}: a symlink") if File.symlink?(file)
                end
                found.select { File.file?(it) }.map do |file|
                    item(name, file.delete_prefix("#{source.chomp("/")}/"),
                         file)
                end
            end

            def item(name, path, file)
                item = Item.new(name:, path:, type: type(name, path, file),
                                bytes: File.binread(file))
                unless item.file.split("/").all? { PART.match?(it) }
                    refuse("#{item.file}: use letters, digits, '.', '-', '_' " \
                           "only, so `mockup: NAME` can name it")
                end
                item
            end

            def type(name, path, file)
                TYPES[File.extname(file).downcase] or
                    refuse("#{[name, path].reject(&:empty?).join("/")}: the " \
                           "viewer does not serve this kind of file " \
                           "(#{TYPES.keys.sort.join(", ")})")
            end
        end

        # The rows a `mockup` writes through its change: the pictures, and
        # the question's own list of them.
        class Placement
            def initialize(change, db)
                @change = change
                @db = db
            end

            # Stores ITEMS and shows NAMES on QUESTION (a row): `replace`
            # takes the question's other pictures away, a pending one gives
            # way to the first.
            def call(question, items, names, replace:)
                taken = items.map(&:name).uniq.select { placed?(it) }
                if taken.any?
                    refuse("#{taken.join(", ")}: already a picture of this " \
                           "ledger; place it under another name")
                end

                items.each { store(it) }
                show(question[:id], names, replace)
            end

            private

            def refuse(message) = raise(Refused, message)

            def placed?(name)
                @db[:pictures].where(ledger_id: @change.ledger_id, name:).any?
            end

            def store(item)
                @change.insert(:pictures, name: item.name, path: item.path,
                                          type: item.type,
                                          bytes: Sequel.blob(item.bytes))
            end

            def show(question_id, names, replace)
                rows = rows_of(question_id, replace)
                first = rows.empty? ? 0 : rows.last[:position] + 1
                rest = fill(rows.find { it[:pending_id] }, names)
                rest.each_with_index do |name, at|
                    add(question_id, name, first + at)
                end
            end

            # The question's rows, none when `replace` took them away.
            def rows_of(question_id, replace)
                rows = @db[:question_pictures].where(question_id:)
                                              .order(:position, :id).all
                return rows unless replace

                rows.each { @change.delete(:question_pictures, it[:id]) }
                []
            end

            def add(question_id, name, position)
                @change.insert(:question_pictures, question_id:, name:,
                                                   position:)
            end

            # NAMES the pending row does not take: it takes the first.
            def fill(pending, names)
                return names unless pending

                @change.update(:question_pictures, pending[:id],
                               name: names.first, pending_id: nil)
                names.drop(1)
            end
        end

        # The rows a `mockup --piece` writes through its change: the
        # picture, and the piece's row naming it as one side.
        class Sides < Placement
            # Stores ITEM and names it as ROLE (before or after) of PIECE
            # (a row); `replace` takes the piece's earlier ROLE away, and
            # without it a second ROLE is refused.
            def call(piece, role, item, replace:)
                old = earlier(piece, role, replace)
                if placed?(item.name)
                    refuse("#{item.name}: already a picture of this " \
                           "ledger; place it under another name")
                end

                store(item)
                old.each { @change.delete(:piece_pictures, it[:id]) }
                @change.insert(:piece_pictures, piece_id: piece[:id],
                                                position: position(role),
                                                role:, name: item.name)
            end

            private

            # The piece's ROLE rows, refused without `replace`.
            def earlier(piece, role, replace)
                old = @db[:piece_pictures].where(piece_id: piece[:id], role:)
                                          .all
                return old if old.empty? || replace

                refuse("P#{piece[:n]} has its #{role} " \
                       "(#{old.map { it[:name] }.join(", ")}); add " \
                       "--replace to swap it")
            end

            # before first, after second: the order the pair is drawn in.
            def position(role) = role == "before" ? 0 : 1
        end
    end
end
