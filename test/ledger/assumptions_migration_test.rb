# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "ledger"

# Migration 007 on a journal written before it: each ledger given an A
# counter at 0, and the assumptions' CHECKs: a text and a check, one of
# three states, no fact while open, a see naming one item, a link naming
# one piece or one question.
class AssumptionsMigrationTest < Minitest::Test
    def setup
        @dir = Dir.mktmpdir("ledger-migration-test")
        @db = Sequel.sqlite(File.join(@dir, "journal.db"),
                            foreign_keys: true)
        Sequel.extension :migration
        migrate(6)
        @ledger = ledger
        migrate
    end

    def teardown
        @db.disconnect
        FileUtils.rm_rf(@dir)
    end

    def test_each_ledger_has_an_a_counter_at_zero
        assert_equal({ @ledger => 0 },
                     @db[:counters].where(kind: "A").to_hash(:ledger_id, :last))
    end

    def test_the_counters_take_a_and_nothing_else_new
        assert_raises(Sequel::CheckConstraintViolation) do
            @db[:counters].insert(ledger_id: @ledger, kind: "B")
        end
    end

    def test_an_open_assumption_names_no_fact
        assert assumption(state: "open")
        refused(state: "open", fact_id: fact)
    end

    # The check rule, not the schema, says a settled one names its fact.
    def test_a_settled_assumption_takes_its_fact
        assert assumption(state: "refuted", fact_id: fact)
        assert assumption(state: "confirmed")
    end

    def test_a_see_names_one_item
        id = assumption(state: "open")
        assert @db[:assumption_sees].insert(assumption_id: id, position: 0,
                                            fact_id: fact)
        assert_raises(Sequel::CheckConstraintViolation) do
            @db[:assumption_sees].insert(assumption_id: id, position: 1)
        end
    end

    def test_text_check_and_state_are_checked
        refused(text: "")
        refused(check: "")
        refused(state: "maybe")
    end

    def test_a_link_names_one_piece_or_one_question
        id = assumption(state: "open")
        piece = @db[:pieces].insert(ledger_id: @ledger, n: 1,
                                    status: "planned", model: "sonnet",
                                    effort: "low", dash: false, title: "P")
        assert @db[:assumption_links].insert(assumption_id: id,
                                             piece_id: piece)
        assert_raises(Sequel::CheckConstraintViolation) do
            @db[:assumption_links].insert(assumption_id: id)
        end
    end

    private

    def migrate(target = nil)
        Sequel::Migrator.run(@db, Ledger::Journal::MIGRATIONS,
                             table: Ledger::Journal::SCHEMA_TABLE, target:)
    end

    def ledger
        id = @db[:ledgers].insert(place: "/work/one", name: "",
                                  project: "one", created_at: 0)
        %w[P O D C F N X G].each do |kind|
            @db[:counters].insert(ledger_id: id, kind:)
        end
        id
    end

    def assumption(**columns)
        @db[:assumptions].insert(ledger_id: @ledger, n: next_n, text: "t",
                                 check: "c", **columns)
    end

    def next_n = (@db[:assumptions].max(:n) || 0) + 1

    def fact
        @db[:facts].insert(ledger_id: @ledger, n: 1 + @db[:facts].count,
                           text: "t", pointer: "p")
    end

    def refused(**columns)
        assert_raises(Sequel::CheckConstraintViolation) do
            assumption(state: "open", **columns)
        end
    end
end
