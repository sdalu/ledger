# frozen_string_literal: true

require "digest"

module LedgerViewer
    module Render
        # A digest of every ledger's files (path, size, mtime) and of its
        # pictures: changes when one does. ledger-serve.py's stamp(),
        # byte for byte, down to the order a folder is listed in.
        module Stamp
            SIDES = ["", ".inbox", ".inbox.taken", ".asked"].freeze

            def self.of(entries)
                digest = Digest::SHA1.new
                entries.sort_by(&:id).each do |entry|
                    paths(entry).each { digest << line(it) }
                end
                digest.hexdigest[0, 16]
            end

            def self.paths(entry)
                SIDES.map { entry.path + it } + pictures(entry.mockups)
            end

            # The files under a folder, each folder's own files sorted,
            # its subfolders in the order they are listed (a symlink to
            # a folder is neither a file nor entered).
            def self.pictures(dir)
                names = Dir.children(dir)
                folders, files = names.partition do |name|
                    File.directory?(File.join(dir, name))
                end
                files.sort.map { File.join(dir, it) } +
                    folders.flat_map { sub(File.join(dir, it)) }
            rescue SystemCallError
                []
            end

            def self.sub(path) = File.symlink?(path) ? [] : pictures(path)

            def self.line(path)
                info = File.stat(path)
                nanos = (info.mtime.to_i * 1_000_000_000) + info.mtime.nsec
                "#{path}\0#{info.size}\0#{nanos}\n"
            rescue SystemCallError
                "#{path}\0gone\n"
            end
        end
    end
end
