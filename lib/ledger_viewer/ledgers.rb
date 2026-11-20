# frozen_string_literal: true

require "digest"

module LedgerViewer
    # The live ledgers under the configured roots, found afresh each time
    # by the rule ledger-serve.py's discover() uses: a root is searched
    # three levels down for git projects; a project's ledgers are the
    # LEDGER*.md files directly in it or in its .claude/; a root that is
    # a file is a ledger named directly. A closed ledger lives in
    # ledgers-closed/, which is not entered.
    class Ledgers
        DEPTH = 3
        SKIP = %w[.git node_modules vendor ledgers-closed worktrees].freeze
        NAME = /\ALEDGER[[:word:].-]*\.md\z/

        # id: what names a ledger in a URL (never a path); project: the
        # directory it belongs to.
        Entry = Data.define(:id, :path, :project) do
            # The folder of the ledger's pictures, by ledger.py's
            # mockups_dir() rule.
            def mockups
                here = File.dirname(path)
                return File.join(here, "mockups") if
                    File.basename(here) == ".claude"
                return File.join(here, ".claude", "mockups") if
                    File.exist?(File.join(here, ".git"))

                File.join(here, "mockups")
            end
        end

        def initialize(roots) = @roots = roots

        # Every live ledger, one per path, in the order the search found
        # them: the order ledger-serve.py's discover() gives, which the
        # index's ties are broken by.
        def all
            found = {}
            @roots.each { search(it, found) }
            found.values
        end

        private

        def search(root, found)
            if File.file?(root)
                add(found, root, File.dirname(File.expand_path(root)))
            else
                walk(File.expand_path(root), 0, found)
            end
        end

        def add(found, path, project)
            path = File.expand_path(path)
            id = Digest::SHA1.hexdigest(path)[0, 10]
            found[id] = Entry.new(id:, path:, project:)
        end

        def walk(dir, depth, found)
            ledgers_in(dir, found) if File.exist?(File.join(dir, ".git"))
            return if depth == DEPTH

            subdirectories(dir).each { walk(it, depth + 1, found) }
        end

        def ledgers_in(dir, found)
            [dir, File.join(dir, ".claude")].each do |sub|
                names(sub).each do |name|
                    path = File.join(sub, name)
                    add(found, path, dir) if File.file?(path)
                end
            end
        end

        def names(dir)
            Dir.children(dir).sort.grep(NAME)
        rescue SystemCallError
            []
        end

        # Real directories only: a symlink is not followed, a dot
        # directory or a skipped name is not entered.
        def subdirectories(dir)
            Dir.children(dir).sort.filter_map do |name|
                next if name.start_with?(".") || SKIP.include?(name)

                path = File.join(dir, name)
                path if File.lstat(path).directory?
            end
        rescue SystemCallError
            []
        end
    end
end
