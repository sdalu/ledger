# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "ledger"

# Migration 019 on a journal written before it: the pictures' bytes
# moved into picture_blobs, one blob per distinct content, each row
# pointing to its own, the bytes column gone and the rows otherwise as
# they were.
class PictureBlobsMigrationTest < Minitest::Test
    PNG = "\x89PNG\r\n\x00\xFF".b
    SVG = "<svg/>".b

    def setup
        @dir = Dir.mktmpdir("ledger-migration-test")
        @db = Sequel.sqlite(File.join(@dir, "journal.db"),
                            foreign_keys: true)
        Sequel.extension :migration
        migrate(18)
        @one = ledger("one")
        @two = ledger("two")
    end

    def teardown
        @db.disconnect
        FileUtils.rm_rf(@dir)
    end

    def test_one_blob_per_distinct_content
        picture(@one, "a.png", PNG)
        picture(@one, "b.png", PNG)
        picture(@two, "c.png", PNG)
        picture(@two, "d.svg", SVG)
        migrate

        expected = [PNG, SVG].to_h { [Digest::SHA256.hexdigest(it), it.size] }
        assert_equal expected, @db[:picture_blobs].to_hash(:sha256, :size)
    end

    def test_every_row_keeps_its_bytes_and_its_columns
        picture(@one, "a.png", PNG)
        picture(@two, "d.svg", SVG)
        before = rows(@db[:pictures])
        migrate

        after = rows(@db[:pictures].join(:picture_blobs, sha256: :sha256))
        assert_equal(before, after.map { it.except(:sha256, :size) })
    end

    def test_the_bytes_column_goes_and_the_journal_is_sound
        picture(@one, "a.png", PNG)
        migrate

        refute_includes @db[:pictures].columns, :bytes
        assert_equal ["ok"], @db["PRAGMA integrity_check"].map(&:values)
                                                          .flatten
        assert_empty @db["PRAGMA foreign_key_check"].all
    end

    def test_a_row_without_its_blob_is_refused
        migrate
        event = @db[:events].insert(ledger_id: @one, at: 0, actor: "cli",
                                    command: "mockup", argv: "[]")

        assert_raises(Sequel::ForeignKeyConstraintViolation) do
            @db[:pictures].insert(ledger_id: @one, name: "x.png", path: "",
                                  type: "image/png", sha256: "0" * 64,
                                  event_id: event)
        end
    end

    private

    # The rows of SET in id order, their bytes as binary strings.
    def rows(set)
        set.order(Sequel[:pictures][:id]).all
           .map { it.merge(bytes: it[:bytes].to_s.b) }
    end

    def migrate(target = nil)
        Sequel::Migrator.run(@db, Ledger::Journal::MIGRATIONS,
                             table: Ledger::Journal::SCHEMA_TABLE, target:)
    end

    def ledger(name)
        @db[:ledgers].insert(place: "/work/#{name}", name: "",
                             project: name, created_at: 0)
    end

    def picture(ledger_id, name, bytes)
        event = @db[:events].insert(ledger_id:, at: 0, actor: "cli",
                                    command: "mockup", argv: "[]")
        @db[:pictures].insert(ledger_id:, name:, path: "", type: "image/png",
                              bytes: Sequel.blob(bytes), event_id: event)
    end
end
