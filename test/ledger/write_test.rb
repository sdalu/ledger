# frozen_string_literal: true

require_relative "helper"

# The write transaction: its events row, the event_rows lines, the
# rollback, the counters, the checks hook and the bytes.
class WriteEventTest < JournalTest
    AT = 1_700_000_000_000

    def test_one_event_per_command_with_actor_argv_and_summary
        argv = ["new", "--title", "T"]
        result = write("piece", argv, actor: "cli", at: AT) do |change|
            change.summary = "P1"
            piece(change)
        end

        assert_equal [result.event], events
        assert_equal argv, JSON.parse(result.event[:argv])
        assert_equal({ at: AT, actor: "cli", command: "piece", summary: "P1" },
                     result.event.slice(:at, :actor, :command, :summary))
    end

    def test_the_actor_is_the_session_when_one_is_set
        ENV["CLAUDE_CODE_SESSION_ID"] = "abc"

        assert_equal "session:abc", Ledger::Write.actor
        ENV.delete("CLAUDE_CODE_SESSION_ID")

        assert_equal "cli", Ledger::Write.actor
    end

    def test_every_row_change_leaves_its_before_and_after
        write do |change|
            id = piece(change)
            change.update(:pieces, id, title: "Renamed")
            change.delete(:pieces, id)
        end

        assert_equal [[nil, "Piece 1"], ["Piece 1", "Renamed"],
                      ["Renamed", nil]], titles(event_rows)
        assert_equal ["pieces"], event_rows.map { it[:tbl] }.uniq
    end

    def test_the_before_and_after_snapshots_are_the_results
        result = write { piece(it) }

        assert_empty result.before.pieces
        assert_equal(["Piece 1"], result.after.pieces.map { it[:title] })
        assert_equal result.after, Ledger::Snapshot.read(db, @ledger[:id])
    end

    def test_an_exception_rolls_back_the_rows_and_the_event
        assert_raises(RuntimeError) do
            write do |change|
                piece(change)
                raise "the command gave up"
            end
        end

        assert_empty events
        assert_empty event_rows
        assert_empty db[:pieces].all
    end

    def test_a_schema_violation_rolls_back_too
        assert_raises(Sequel::CheckConstraintViolation) do
            write { piece(it, status: "kept") }
        end

        assert_empty events
    end

    def test_a_dry_run_writes_nothing_and_keeps_the_result
        result = write(dry: true) { piece(it) }

        assert_predicate result, :dry
        assert_equal 1, result.after.pieces.size
        assert_empty events
        assert_empty db[:pieces].all
    end

    def test_an_unknown_address_is_refused_before_anything
        assert_raises(Ledger::Unknown) do
            Ledger::Write.run(@journal, "/else/LEDGER.md", "piece", []) { 1 }
        end

        assert_empty events
    end

    def test_an_unknown_option_is_an_error
        assert_raises(ArgumentError) { write(wet: true) { 1 } }
    end

    private

    # The title before and after, per event_rows line.
    def titles(rows)
        rows.map do |row|
            [row[:before], row[:after]].map { it && JSON.parse(it)["title"] }
        end
    end
end

class WriteCounterTest < JournalTest
    def test_ids_are_sequential_within_and_across_writes
        first = write { |c| [c.next_id("P"), c.next_id("P"), c.next_id("O")] }
        second = write { it.next_id("P") }

        assert_equal [1, 2, 1], first.value
        assert_equal 3, second.value
    end

    def test_an_id_a_rolled_back_write_took_was_never_given
        assert_raises(RuntimeError) { write { |c| c.next_id("P") && raise } }

        assert_equal 1, write { it.next_id("P") }.value
    end

    def test_an_id_whose_item_was_undone_is_never_given_again
        id = write { piece(it) }.value
        write("undo") { it.delete(:pieces, id) }

        assert_empty db[:pieces].all
        assert_equal 2, write { it.next_id("P") }.value
    end

    def test_an_unknown_kind_has_no_counter
        assert_raises(Ledger::Unknown) { write { it.next_id("Q") } }
    end
end

class WriteChecksTest < JournalTest
    # A rule runner that fails `titles` on every piece titled "bad".
    CHECKS = lambda do |snapshot|
        snapshot.pieces.filter_map do |piece|
            ["titles", "P#{piece[:n]}: bad"] if piece[:title] == "bad"
        end
    end

    def test_a_write_that_fails_a_rule_before_passed_rolls_back
        error = assert_raises(Ledger::Worse) do
            write(checks: CHECKS) { piece(it, title: "bad") }
        end

        assert_equal "FAIL titles -- P1: bad", error.message
        assert_empty events
    end

    def test_a_failure_before_passes_unless_it_names_the_id_written
        write { piece(it, title: "bad") }
        write(checks: CHECKS) { piece(it) }

        assert_equal 2, db[:pieces].count
        assert_raises(Ledger::Worse) do
            write(checks: CHECKS, own: "P3") { piece(it, title: "bad") }
        end
        assert_equal 2, db[:pieces].count
    end
end

class WriteBytesTest < JournalTest
    TEXT = "il\u00A0dit\u00A0\u00AB\u202Fnon\u202F\u00BB, l\u2019os  "
    BYTES = (0..255).map(&:chr).join.b.freeze

    def test_verbatim_columns_keep_every_byte
        id = write { it.insert(:noticed, line: TEXT) }.value

        assert_bytes TEXT, db[:noticed].where(id:).get(:line)
        assert_bytes TEXT, snapshot.noticed[0][:line]
    end

    def test_the_history_keeps_every_byte_too
        write { it.insert(:noticed, line: TEXT) }

        assert_bytes TEXT, JSON.parse(event_rows.fetch(0)[:after])["line"]
    end

    def test_a_picture_keeps_its_bytes_and_stays_out_of_the_history
        write("mockup") { picture(it) }

        assert_bytes BYTES, db[:pictures].get(:bytes).to_s
        assert_empty event_rows
        refute_includes snapshot.pictures[0], :bytes
    end

    private

    def assert_bytes(expected, actual) = assert_equal(expected.b, actual.b)

    def snapshot = Ledger::Snapshot.read(db, @ledger[:id])

    def picture(change)
        change.insert(:pictures, name: "m", path: "", type: "image/png",
                                 bytes: Sequel.blob(BYTES))
    end
end

class WriteLinkTest < JournalTest
    def test_an_edge_is_resolved_to_rows_inside_the_transaction
        write do |change|
            piece(change)
            decision(change)
            change.link("led_to", "X1", "P1")
        end
        link = db[:links].first

        assert_equal({ kind: "led_to", from_kind: "X", from_row: 1,
                       to_kind: "P", to_row: 1, event_id: 1 },
                     link.except(:id, :ledger_id))
    end

    def test_a_target_that_is_not_this_ledgers_is_refused
        write { piece(it) }
        error = assert_raises(Ledger::Unknown) do
            write do |change|
                decision(change)
                change.link("led_to", "X1", "P9")
            end
        end

        assert_equal "P9 is not this ledger's", error.message
        assert_empty db[:decisions].all
    end

    def test_an_edge_the_schema_forbids
        assert_raises(Sequel::CheckConstraintViolation) do
            write do |change|
                piece(change)
                piece(change)
                change.link("answers", "P1", "P2")
            end
        end
    end

    private

    def decision(change)
        n = change.next_id("X")
        change.insert(:decisions, n:, date: "2026-11-20", body: "b", by: "me")
    end
end
