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

            # Stores ITEMS and shows NAME on QUESTION (a row): `replace`
            # takes the question's other pictures away, a pending one gives
            # way to it.
            def call(question, items, name, replace:)
                taken = items.map(&:name).uniq.select { placed?(it) }
                if taken.any?
                    refuse("#{taken.join(", ")}: already a picture of this " \
                           "ledger; place it under another name")
                end

                items.each { store(it) }
                show(question[:id], name, replace)
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

            def show(question_id, name, replace)
                rows = @db[:question_pictures].where(question_id:)
                                              .order(:position, :id).all
                return swap(question_id, name, rows) if replace

                pending = rows.find { it[:pending_id] }
                return append(question_id, name, rows) unless pending

                columns = { name:, pending_id: nil }
                @change.update(:question_pictures, pending[:id], **columns)
            end

            def swap(question_id, name, rows)
                rows.each { @change.delete(:question_pictures, it[:id]) }
                @change.insert(:question_pictures, question_id:, position: 0,
                                                   name:)
            end

            def append(question_id, name, rows)
                position = rows.empty? ? 0 : rows.last[:position] + 1
                @change.insert(:question_pictures, question_id:, position:,
                                                   name:)
            end
        end
    end
end
