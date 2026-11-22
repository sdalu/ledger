# frozen_string_literal: true

require "sqlite3"

module Ledger
    # A copy of the journal made with SQLite's online backup, which is
    # consistent while other processes write and carries the WAL.
    module Backup
        STAMP = "%Y%m%d-%H%M%S"

        class Exists < StandardError; end

        module_function

        # The file a purge of ledger ID copies the journal to, beside it.
        def purge_path(journal_path, id, at: Time.now)
            "#{journal_path}.before-purge-L#{id}-#{at.strftime(STAMP)}"
        end

        # The file a vacuum copies the journal to, beside it.
        def vacuum_path(journal_path, at: Time.now)
            "#{journal_path}.before-vacuum-#{at.strftime(STAMP)}"
        end

        # DB's journal copied to PATH, which must not exist; the copy is
        # private (the journal holds password hashes). Exists when PATH is
        # there.
        def copy(db, path)
            create(path)
            into = SQLite3::Database.new(path)
            db.synchronize { run(it, into) }
        ensure
            into&.close
        end

        def create(path)
            flags = File::WRONLY | File::CREAT | File::EXCL
            File.open(path, flags, 0o600, &:close)
        rescue Errno::EEXIST
            raise Exists, "#{path} exists"
        end

        def run(source, target)
            backup = SQLite3::Backup.new(target, "main", source, "main")
            backup.step(-1)
            backup.finish
        end
    end
end
