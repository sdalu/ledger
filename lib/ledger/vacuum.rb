# frozen_string_literal: true

require "sqlite3"

require "ledger/backup"

module Ledger
    # VACUUM of the journal, only while no other connection holds the
    # write lock, then after a backup copy: VACUUM rewrites the whole
    # file, so a writer racing it would be waiting on, or losing to, the
    # rewrite, and a refusal must leave no copy behind.
    class Vacuum
        BUSY_MS = 5_000

        class Busy < StandardError; end

        # The pages as SQLite counts them and the bytes on disk, the
        # journal file and its -wal apart.
        Sizes = Data.define(:pages, :free, :page_size, :file, :wal) do
            def bytes = pages * page_size
            def free_bytes = free * page_size
            def disk = file + wal
        end

        def initialize(journal, at: Time.now)
            @journal = journal
            @at = at
        end

        def sizes
            path = @journal.path
            Sizes.new(pages: pragma(:page_count), free: pragma(:freelist_count),
                      page_size: pragma(:page_size),
                      file: disk(path), wal: disk("#{path}-wal"))
        end

        # [backup path, sizes before, sizes after]; Busy when another
        # connection writes, Backup::Exists when the backup name is taken.
        # The checkpoint after VACUUM moves the rewrite out of the -wal so
        # the file itself shrinks.
        def run
            ensure_quiet
            path = Backup.vacuum_path(@journal.path, at: @at)
            Backup.copy(@journal.db, path)
            before = sizes
            @journal.db.run("VACUUM")
            @journal.db.run("PRAGMA wal_checkpoint(TRUNCATE)")
            [path, before, sizes]
        end

        private

        def pragma(name) = @journal.db.fetch("PRAGMA #{name}").single_value

        def disk(path) = File.exist?(path) ? File.size(path) : 0

        # The write lock taken and released at once: it proves no other
        # connection holds it, within the busy timeout.
        def ensure_quiet
            lock = SQLite3::Database.new(@journal.path)
            lock.busy_timeout = BUSY_MS
            lock.execute("BEGIN IMMEDIATE")
            lock.execute("ROLLBACK")
        rescue SQLite3::BusyException
            raise Busy, "another session is writing the journal; try again"
        ensure
            lock&.close
        end
    end
end
