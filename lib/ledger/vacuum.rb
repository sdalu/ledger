# frozen_string_literal: true

require "sqlite3"

require "ledger/backup"

module Ledger
    # VACUUM of the journal, after a backup copy and only while no other
    # connection holds the write lock: VACUUM rewrites the whole file, so
    # a writer racing it would be waiting on, or losing to, the rewrite.
    class Vacuum
        BUSY_MS = 5_000

        class Busy < StandardError
            attr_reader :backup

            def initialize(message, backup:)
                super(message)
                @backup = backup
            end
        end

        Sizes = Data.define(:pages, :free, :page_size) do
            def bytes = pages * page_size
            def free_bytes = free * page_size
        end

        def initialize(journal, at: Time.now)
            @journal = journal
            @at = at
        end

        # The journal's page_count, freelist_count and page_size.
        def sizes
            Sizes.new(**%i[page_count freelist_count page_size].zip(
                %i[pages free page_size]
            ).to_h { |pragma, key| [key, pragma(pragma)] })
        end

        # The backup path; Backup::Exists when the name is taken, Busy
        # when another connection writes. Returns [path, before, after].
        def run
            path = Backup.vacuum_path(@journal.path, at: @at)
            Backup.copy(@journal.db, path)
            before = sizes
            ensure_quiet(path)
            @journal.db.run("VACUUM")
            [path, before, sizes]
        end

        private

        def pragma(name) = @journal.db.fetch("PRAGMA #{name}").single_value

        # The write lock taken and released at once: it proves no other
        # connection holds it, within the busy timeout.
        def ensure_quiet(backup)
            lock = SQLite3::Database.new(@journal.path)
            lock.busy_timeout = BUSY_MS
            lock.execute("BEGIN IMMEDIATE")
            lock.execute("ROLLBACK")
        rescue SQLite3::BusyException
            raise Busy.new("another session is writing the journal; " \
                           "try again", backup:)
        ensure
            lock&.close
        end
    end
end
