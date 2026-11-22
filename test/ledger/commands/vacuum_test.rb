# frozen_string_literal: true

require "sqlite3"

require_relative "helper"
require "ledger/vacuum"

# `vacuum`: a dry run writes nothing; a vacuum keeps every row and gives
# the free pages back after a backup; another writer or a taken backup
# name refuses it.
class VacuumTest < CommandCase
    def setup
        super
        db.run("CREATE TABLE bulk (id INTEGER PRIMARY KEY, pad BLOB)")
        400.times { db[:bulk].insert(pad: Sequel.blob("x" * 4000)) }
        db[:bulk].delete
        db.run("PRAGMA wal_checkpoint(TRUNCATE)")
    end

    def backups = Dir.glob("#{@journal.path}.before-vacuum-*")

    def totals = db.tables.to_h { [it, db[it].count] }

    def test_a_dry_run_prints_the_sizes_and_writes_nothing
        bytes = File.binread(@journal.path)
        code, out, = cli("vacuum", "--dry-run")
        assert_equal 0, code
        assert_match(/^page_count: \d+$/, out)
        assert_match(/^freelist_count: [1-9]\d*$/, out)
        assert_match(/^page_size: \d+$/, out)
        assert_equal bytes, File.binread(@journal.path)
        assert_empty backups
    end

    def test_a_vacuum_shrinks_the_journal
        assert_operator free_pages, :>, 0
        out = ok("vacuum")
        assert_equal 0, free_pages
        before, now = out.scan(/^(?:before|after): (\d+) bytes/).flatten
        assert_operator now.to_i, :<, before.to_i
    end

    def test_a_vacuum_names_its_backup
        out = ok("vacuum")
        assert_equal "backup: #{backups.first}", out.lines.last.chomp
    end

    def test_the_size_after_is_the_file_on_disk
        out = ok("vacuum")
        journal = File.size(@journal.path)
        assert_match(/^after: #{journal} bytes \(journal #{journal} \+ wal 0\)/,
                     out)
    end

    def free_pages = Ledger::Vacuum.new(@journal).sizes.free

    def test_a_vacuum_keeps_every_row
        rows = totals
        ok("vacuum")
        assert_equal rows, totals
        assert_equal "ok", db.fetch("PRAGMA integrity_check").single_value
        assert_equal 1, backups.size
    end

    def test_another_writer_makes_it_refuse
        other = SQLite3::Database.new(@journal.path)
        other.execute("BEGIN IMMEDIATE")
        code, out, err = cli("vacuum")
        assert_equal 2, code
        assert_includes err, "another session is writing the journal; " \
                             "try again"
        assert_empty out
        assert_empty backups
    ensure
        other&.close
    end

    def test_an_existing_backup_name_is_refused
        at = Time.new(2026, 11, 22, 10, 0, 0)
        File.write(Ledger::Backup.vacuum_path(@journal.path, at:), "x")
        assert_raises(Ledger::Backup::Exists) do
            Ledger::Vacuum.new(@journal, at:).run
        end
        assert_equal 1, backups.size
    end
end
