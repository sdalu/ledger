# frozen_string_literal: true

require_relative "purge_case"

# `purge L<n> --confirmed`: every row of the ledger goes, nothing of the
# other, the journal stays sound, the backup is the way back.
class PurgeRowsTest < PurgeCase
    OWNERS = %i[ledgers pieces questions assumptions events].freeze

    def test_the_fixture_reaches_every_table_a_purge_cleans
        assert_empty @beta_counts.select { |_, n| n.zero? }.keys
    end

    def test_every_table_with_a_ledger_id_is_listed
        owned = db.tables.select { db[it].columns.include?(:ledger_id) }
        assert_empty owned - Ledger::Purge::TABLES.map(&:first)
    end

    def test_every_table_pointing_at_a_ledger_s_rows_is_listed
        pointing = db.tables.select do |table|
            db.foreign_key_list(table).any? { OWNERS.include?(it[:table]) }
        end
        assert_empty pointing - Ledger::Purge::TABLES.map(&:first)
    end

    def test_a_purge_removes_every_row_of_the_ledger
        left = totals.merge(@beta_counts) { |_, all, mine| all - mine }
        out = ok("purge", "L#{@beta}", "--confirmed")
        assert_equal left, totals
        assert_includes out, "  events: #{@beta_counts[:events]}"
    end

    def test_nothing_of_another_ledger_goes
        ok("purge", "L#{@beta}", "--confirmed")
        assert_equal @gamma_counts, counts(@gamma)
        snapshot = Ledger::Snapshot.read(db, @gamma)
        assert_empty(Ledger::Checks.run(snapshot).reject { it[1] })
    end

    def test_the_journal_is_sound_after_a_purge
        ok("purge", "L#{@beta}", "--confirmed")
        assert_equal ["ok"], db["PRAGMA integrity_check"].map(&:values).flatten
        assert_empty db["PRAGMA foreign_key_check"].all
    end

    def test_the_backup_is_the_journal_as_it_was_and_opens
        before = totals
        path = ok("purge", "L#{@beta}", "--confirmed")[/^backup: (.+)$/, 1]
        assert_equal [path], backups
        assert_match(/\.before-purge-L#{@beta}-\d{8}-\d{6}\z/, path)
        copy = Sequel.sqlite(path)
        assert_equal(before, copy.tables.to_h { [it, copy[it].count] })
        copy.disconnect
    end

    def test_a_purge_is_not_an_event_and_is_not_undone
        ok("purge", "L#{@beta}", "--confirmed")
        assert_equal 0, db[:events].where(command: "purge").count
        assert_equal 0, db[:events].where(ledger_id: @beta).count
        assert_includes cli("undo", BETA)[2], "no live ledger"
    end
end
