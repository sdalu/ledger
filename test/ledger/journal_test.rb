# frozen_string_literal: true

require_relative "helper"

# Opening the journal: the file LEDGER_JOURNAL names, its modes and
# pragmas, both migration sets, and the address a ledger lives at.
class JournalOpenTest < JournalTest
    def test_the_file_is_the_one_the_variable_names
        assert_equal ENV.fetch("LEDGER_JOURNAL"), @journal.path
        assert_path_exists @journal.path
    end

    def test_the_default_path_is_under_the_state_directory
        ENV.delete("LEDGER_JOURNAL")

        default = File.expand_path("~/.local/state/orchestration/journal.db")

        assert_equal default, Ledger::Journal.path
    end

    def test_the_file_is_private_and_its_directory_too
        assert_equal 0o600, File.stat(@journal.path).mode & 0o777
        assert_equal 0o700, File.stat(File.dirname(@journal.path)).mode & 0o777
    end

    def test_wal_foreign_keys_and_the_busy_timeout
        assert_equal "wal", db.fetch("PRAGMA journal_mode").get(:journal_mode)
        assert_equal 1, db.fetch("PRAGMA foreign_keys").get(:foreign_keys)
        assert_equal Ledger::Journal::BUSY_MS,
                     db.fetch("PRAGMA busy_timeout").get(:timeout)
    end

    def test_both_migration_sets_run_and_every_table_is_there
        assert_includes db.tables, :users, "sesam's set"
        assert_includes db.tables, :sesam_schema
        assert_includes db.tables, :ledger_schema
        tables = %i[ledgers counters events event_rows]
        missing = Ledger::Snapshot::TABLES + tables - db.tables

        assert_empty missing
    end

    def test_opening_again_is_harmless
        again = Ledger::Journal.open

        assert_equal 1, again.db[:ledgers].count
    ensure
        again&.close
    end

    def test_a_foreign_key_holds
        assert_raises(Sequel::ForeignKeyConstraintViolation) do
            db[:facts].insert(ledger_id: 99, n: 1, text: "t", pointer: "p")
        end
    end

    # 004 rebuilt pieces: 'deferred' and its `until` taken, the other
    # CHECKs, the unique (ledger, n) and the tables naming pieces kept.
    def deferred_piece
        { ledger_id: @ledger[:id], status: "deferred", model: "opus",
          effort: "low", dash: false, title: "t", until: "later" }
    end

    def test_pieces_take_deferred_and_keep_their_checks
        db[:pieces].insert(n: 1, **deferred_piece)

        assert_equal "later", db[:pieces].get(:until)
        [{ n: 2, status: "gone" }, { n: 3, model: "gpt" },
         { n: 4, status: "out" }].each do |change|
            assert_raises(Sequel::CheckConstraintViolation) do
                db[:pieces].insert(**deferred_piece, **change)
            end
        end
    end

    def test_pieces_keep_their_unique_and_the_keys_naming_them
        db[:pieces].insert(n: 1, **deferred_piece)
        assert_raises(Sequel::UniqueConstraintViolation) do
            db[:pieces].insert(n: 1, **deferred_piece)
        end
        %i[piece_links piece_awaits piece_returns].each do |table|
            assert_includes db.foreign_key_list(table).map { it[:table] },
                            :pieces
        end
    end

    def test_the_schema_refuses_what_a_check_rule_used_to_catch
        assert_raises(Sequel::CheckConstraintViolation) do
            db[:facts].insert(ledger_id: @ledger[:id], n: 1, text: "t",
                              pointer: "")
        end
        assert_raises(Sequel::CheckConstraintViolation) do
            db[:decisions].insert(ledger_id: @ledger[:id], n: 1, by: "them",
                                  date: "2026-11-20", body: "b")
        end
    end
end

class AddressTest < JournalTest
    def test_an_address_is_the_path_the_file_had
        address = Ledger::Address.parse("/work/alpha/LEDGER.md")

        assert_equal "/work/alpha", address.place
        assert_equal "", address.name
        assert_equal "/work/alpha/LEDGER.md", address.to_s
    end

    def test_a_named_ledger_and_a_relative_path
        address = Ledger::Address.parse("sub/LEDGER-web.md")

        assert_equal File.expand_path("sub"), address.place
        assert_equal "web", address.name
    end

    def test_another_file_is_not_an_address
        assert_raises(Ledger::Unknown) { Ledger::Address.parse("x/NOTES.md") }
    end

    def test_the_live_ledger_at_an_address_and_none
        assert_equal @ledger[:id], @journal.ledger(ADDRESS)[:id]
        assert_raises(Ledger::Unknown) { @journal.ledger("/else/LEDGER.md") }
    end

    def test_a_second_live_ledger_at_one_address_is_refused
        assert_raises(Sequel::UniqueConstraintViolation) do
            @journal.create_ledger(ADDRESS, project: "alpha")
        end
    end

    def test_a_closed_ledger_frees_its_address
        db[:ledgers].where(id: @ledger[:id]).update(closed_at: 1)
        fresh = @journal.create_ledger(ADDRESS, project: "alpha")

        assert_equal fresh[:id], @journal.ledger(ADDRESS)[:id]
        assert_equal 9, db[:counters].where(ledger_id: fresh[:id]).count
    end
end
