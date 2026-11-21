# frozen_string_literal: true

require_relative "checks/runner_test"

# The fixture ledger with writes timed, read back as a Derive over its
# events; the base of the tests below.
class DeriveCase < CheckCase
    AT = 1_700_000_000_000
    MINUTE = 60_000

    def row(id) = derive.piece(id)

    def read_derive(now)
        Ledger::Derive.read(db, snapshot, now:, stall_minutes: 60)
    end

    def piece_row(change, **columns)
        change.insert(:pieces, n: change.next_id("P"), status: "planned",
                               model: "opus", effort: "low", dash: false,
                               title: "Some piece", **columns)
    end

    def question_row(change, **columns)
        change.insert(:questions, n: change.next_id("O"), title: "A question",
                                  detail: "Which one?", **columns)
    end
end

# The derived states of section 3.
class DeriveTest < DeriveCase
    def test_the_stall_budget_is_sixty_minutes_unless_overridden
        assert_equal 60, Ledger::Derive.parse_stall(nil)
        assert_equal 15, Ledger::Derive.parse_stall("15")
    end

    def test_a_stall_budget_not_a_whole_number_above_zero_is_refused
        %w[0 -5 1.5 soon].each do |value|
            assert_raises(Ledger::Refused) { Ledger::Derive.parse_stall(value) }
        end
    end

    def test_ready_is_planned_with_every_after_piece_settled
        done = piece(status: "verified", evidence: "ok")
        waiting = piece
        ready = piece
        blocked = piece
        after(ready, done)
        after(blocked, done, waiting)

        assert_equal([true, false],
                     [ready, blocked].map { derive.ready?(row(it)) })
    end

    def test_in_flight_is_blocked_back_out_planned_deferred
        piece(status: "deferred", until: "three closures")
        piece
        piece(status: "out", claimed_by: "s")
        piece(status: "blocked")
        piece(status: "back")

        assert_equal(%w[P4 P5 P3 P2 P1],
                     derive.in_flight.map { derive.ref(it) })
    end

    def test_an_out_piece_untouched_past_the_budget_is_stalled
        out_at(AT)

        refute stalled?(AT + (59 * MINUTE))
        assert stalled?(AT + (61 * MINUTE))
    end

    def test_a_row_of_the_piece_tables_touches_the_piece
        id = out_at(AT)
        write(at: AT + (30 * MINUTE)) do |change|
            change.insert(:piece_scopes, piece_id: id, position: 0,
                                         word: "commit", text: "it")
        end

        refute stalled?(AT + (61 * MINUTE))
    end

    def test_stalled_needs_the_events
        assert_raises(ArgumentError) { derive.stalled?(row(piece)) }
    end

    def test_asked_since_is_the_later_of_insert_and_preparer_settled
        prep = write(at: AT) { piece_row(it) }.value
        write(at: AT + 1) { question_row(it, by_id: prep) }
        write(at: AT + 2) do |change|
            change.update(:pieces, prep, status: "verified", evidence: "ok",
                                         verified_by: "me")
            change.insert(:piece_awaits, piece_id: prep, position: 0,
                                         word: "commit")
        end

        assert_equal({ "O1" => AT + 2, "P1:commit" => AT + 2 },
                     read_derive(AT).asked_since)
    end

    def test_a_question_being_prepared_has_no_asked_since
        prep = write(at: AT) { piece_row(it) }.value
        write(at: AT + 1) { question_row(it, by_id: prep) }

        assert_empty read_derive(AT).asked_since
    end

    private

    def stalled?(now) = read_derive(now).stalled?(read_derive(now).pieces[0])

    def out_at(at)
        write(at:) { piece_row(it, status: "out", claimed_by: "s") }.value
    end
end

# The status line: its wording and order, `stalled:` after
# blocked.
class StatusLineTest < DeriveCase
    def test_the_status_line_names_every_state
        pieces_fixture
        open_fixture

        assert_equal "Status (Ledger in Ruby) — criteria 1/2 · " \
                     "pieces 1/6 verified, 1 kept · " \
                     "out: P1 · back: P2 · blocked: P3 · deferred: P7 " \
                     "(three closures), P8 (the next release) · " \
                     "stalled: P1 · " \
                     "waiting on you: O1 · being prepared: O2 (P3) · your " \
                     "word: P4 (commit, other (look)) · from the viewer: N1",
                     line
    end

    def test_a_finished_ledger_proposes_to_close
        assert_equal "Status (Ledger in Ruby) — criteria 1/1 · " \
                     "pieces 0/0 verified · done: propose close", line
    end

    def test_a_malformed_entry_is_named_and_holds_back_the_close
        entry(n: 4, malformed: true)

        assert_equal "Status (Ledger in Ruby) — criteria 1/1 · " \
                     "pieces 0/0 verified · from the viewer: N4", line
    end

    def test_the_beat_counts_an_unchanged_line
        beat = Ledger::Derive::StatusLine.method(:beat)

        assert_equal [2, "L · unchanged ×2"], beat.call("L", "L", 1)
        assert_equal [0, "L"], beat.call("L", "M", 3)
    end

    private

    def line = Ledger::Derive::StatusLine.new(read_derive(AT)).to_s

    def entry(**columns)
        @rows.insert(:inbox_entries, n: 1, at: "2026-11-20 10:00:00",
                                     payload: "{}", **columns)
    end

    def pieces_fixture
        criterion
        piece(status: "out", claimed_by: "s")
        piece(status: "back")
        piece(status: "blocked")
        awaits_other(piece(status: "verified", evidence: "ok"))
        piece(status: "kept", model: nil, effort: nil, kept_reason: "mine")
        piece(status: "dropped")
        piece(status: "deferred", until: "three closures")
        piece(status: "deferred", until: "the next release")
    end

    # O1 answerable, O2 prepared by the blocked P3, N1 pending, N2 taken.
    def open_fixture
        question
        question(["C = one", "D = two"], by_id: db[:pieces].where(n: 3)
                                                           .get(:id))
        entry
        entry(n: 2, taken_id: event)
    end

    def awaits_other(id)
        awaits(id, "commit")
        @rows.insert(:piece_awaits, piece_id: id, position: 1, word: "other",
                                    what: "look")
    end
end
