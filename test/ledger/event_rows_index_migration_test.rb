# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "ledger"

# Migration 017: event_rows indexed by event_id, so that the join every
# reader makes from one ledger's events to the rows they changed is a
# search per event rather than a scan of the whole table per event.
class EventRowsIndexMigrationTest < Minitest::Test
    INDEX = "event_rows_event_id_index"

    def setup
        @dir = Dir.mktmpdir("ledger-migration-test")
        @db = Sequel.sqlite(File.join(@dir, "journal.db"),
                            foreign_keys: true)
        Sequel.extension :migration
    end

    def teardown
        @db.disconnect
        FileUtils.rm_rf(@dir)
    end

    def test_the_journal_holds_the_index
        migrate

        assert_equal [:event_id],
                     @db.indexes(:event_rows).dig(INDEX.to_sym, :columns)
    end

    # The shape of Read.claims, Derive, Stamps, Stats and Write's join.
    def test_the_ledger_join_searches_event_rows_by_the_index
        migrate
        plan = @db.fetch("EXPLAIN QUERY PLAN #{join.sql}").map(:detail)

        assert plan.any? { it.include?("event_rows") && it.include?(INDEX) },
               "plan: #{plan.inspect}"
        refute plan.any? { it.start_with?("SCAN event_rows") },
               "plan: #{plan.inspect}"
    end

    def test_a_journal_already_holding_the_index_migrates
        migrate(16)
        @db.run("CREATE INDEX #{INDEX} ON event_rows (event_id)")
        migrate

        assert_includes @db.indexes(:event_rows).keys, INDEX.to_sym
    end

    private

    def join
        @db[:event_rows].join(:events, id: :event_id)
                        .where(ledger_id: 1)
                        .order(Sequel[:events][:id])
                        .select(:at, :tbl, :row_id, :before, :after)
    end

    def migrate(target = nil)
        Sequel::Migrator.run(@db, Ledger::Journal::MIGRATIONS,
                             table: Ledger::Journal::SCHEMA_TABLE, target:)
    end
end
