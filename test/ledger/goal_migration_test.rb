# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "ledger"

# Migration 006 on a journal written before it: each Goal block given
# its G<n> in id order, ledger by ledger, the G counter at the number of
# blocks, and the done mark empty.
class GoalMigrationTest < Minitest::Test
    def setup
        @dir = Dir.mktmpdir("ledger-migration-test")
        @db = Sequel.sqlite(File.join(@dir, "journal.db"),
                            foreign_keys: true)
        Sequel.extension :migration
        migrate(5)
    end

    def teardown
        @db.disconnect
        FileUtils.rm_rf(@dir)
    end

    def test_blocks_are_numbered_in_id_order_per_ledger
        one = ledger("one")
        two = ledger("two")
        [one, two, one, one].each { goal(it) }
        migrate

        assert_equal [[one, 1], [two, 1], [one, 2], [one, 3]],
                     @db[:goals].order(:id).select_map(%i[ledger_id n])
    end

    def test_the_g_counter_stands_at_the_blocks_given
        one = ledger("one")
        empty = ledger("empty")
        2.times { goal(one) }
        migrate

        assert_equal({ one => 2, empty => 0 },
                     @db[:counters].where(kind: "G")
                                   .to_hash(:ledger_id, :last))
    end

    def test_the_blocks_keep_their_words_and_are_active
        id = goal(ledger("one"))
        before = @db[:goals].where(id:).first
        migrate

        after = @db[:goals].where(id:).first
        assert_equal before, after.except(:n, :done_at, :done_evidence)
        assert_nil after[:done_at]
        assert_nil after[:done_evidence]
    end

    def test_the_old_checks_hold
        rows = migrated_goal

        assert_raises(Sequel::CheckConstraintViolation) do
            rows.update(quote: "")
        end
    end

    def test_the_time_and_the_evidence_go_together
        rows = migrated_goal

        assert_raises(Sequel::CheckConstraintViolation) do
            rows.update(done_at: 1)
        end
        assert_raises(Sequel::CheckConstraintViolation) do
            rows.update(done_evidence: "x")
        end
    end

    private

    # The dataset of one block written before 006, once migrated.
    def migrated_goal
        id = goal(ledger("one"))
        migrate
        @db[:goals].where(id:)
    end

    def migrate(target = nil)
        Sequel::Migrator.run(@db, Ledger::Journal::MIGRATIONS,
                             table: Ledger::Journal::SCHEMA_TABLE, target:)
    end

    def ledger(name)
        id = @db[:ledgers].insert(place: "/work/#{name}", name: "",
                                  project: name, created_at: 0)
        %w[P O D C F N X].each do |kind|
            @db[:counters].insert(ledger_id: id, kind:)
        end
        id
    end

    def goal(ledger_id)
        @db[:goals].insert(ledger_id:, stamp: "2026-11-20, verbatim",
                           date: "2026-11-20", revised: false,
                           title: "A title", quote: "the words")
    end
end
