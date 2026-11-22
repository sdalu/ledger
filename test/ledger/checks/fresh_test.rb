# frozen_string_literal: true

require_relative "runner_test"

# What the pictures-fresh tests share: events at chosen times, pictures
# placed on a piece or a question.
class FreshCase < CheckCase
    # 2026-11-22 09:45 local time, and a minute later.
    PLACED = Time.local(2026, 11, 22, 9, 45).to_i * 1000
    LATER = PLACED + 60_000
    STAMP = "(2026-11-22 09:45)"

    # The rows written from here on carry an event at AT (ms).
    def at(time)
        event = db[:events].insert(ledger_id: @ledger[:id], at: time,
                                   actor: "cli", command: "fixture",
                                   argv: "[]")
        @rows = Ledger::Change.new(db, @ledger, event)
    end

    def picture(piece_id, role = "after")
        name = "#{role}-#{piece_id}-#{db[:pictures].count}.png"
        @rows.insert(:pictures, name:, path: "", type: "image/png",
                                sha256: Ledger::Pictures.blob(db, "png"))
        @rows.insert(:piece_pictures, piece_id:, position: 0, role:, name:)
    end

    def question_picture(question_id)
        name = "q-#{question_id}-#{db[:pictures].count}.png"
        @rows.insert(:pictures, name:, path: "", type: "image/png",
                                sha256: Ledger::Pictures.blob(db, "png"))
        @rows.insert(:question_pictures, question_id:, position: 0, name:)
    end

    # P1, with a plan and a problem, pictured at PLACED.
    def pictured(**columns)
        id = piece(plan: "swap it", problem: "it is slow",
                   detail: "the cache layer", **columns)
        at(PLACED)
        picture(id)
        at(LATER)
        id
    end

    # O1, pictured at PLACED.
    def pictured_question
        id = question
        at(PLACED)
        question_picture(id)
        at(LATER)
        id
    end
end

# pictures-fresh on pieces: a plan, detail or problem reworded after
# the piece's last picture leave it stale; a warning on a plain check, a
# failure on --final, announced instead while it is being redrawn.
class FreshChecksTest < FreshCase
    def test_a_plan_changed_after_the_picture_warns
        update(:pieces, pictured, plan: "swap it twice")

        assert_equal ["pictures-fresh", true,
                      "P1: plan changed after its last picture #{STAMP}"],
                     report("pictures-fresh")
    end

    def test_a_detail_changed_after_the_picture_warns
        update(:pieces, pictured, detail: "the cache and its keys")

        assert_equal "P1: detail changed after its last picture #{STAMP}",
                     report("pictures-fresh")[2]
    end

    def test_a_problem_changed_after_the_picture_warns_and_fields_join
        update(:pieces, pictured, problem: "it is slower", plan: "drop it")

        assert_equal "P1: plan, problem changed after its last picture " \
                     "#{STAMP}", report("pictures-fresh")[2]
    end

    def test_status_evidence_risk_and_route_never_stale_it
        id = pictured
        update(:pieces, id, status: "verified", verified_by: "me",
                            evidence: "seen", risk: "2/10 — small",
                            risk_rating: 2, model: "opus")
        awaits(id, "start")

        assert_passes "pictures-fresh"
    end

    def test_a_picture_placed_after_the_change_clears_it
        id = pictured
        update(:pieces, id, plan: "swap it twice")
        at(LATER + 60_000)
        picture(id, "before")

        assert_passes "pictures-fresh"
    end

    def test_a_field_first_set_after_the_picture_is_no_change
        id = piece(plan: "swap it")
        at(PLACED)
        picture(id)
        at(LATER)
        update(:pieces, id, detail: "the cache layer", problem: "it is slow")

        assert_passes "pictures-fresh", final: true
    end

    def test_a_rewording_taken_back_is_fresh_again
        id = pictured
        update(:pieces, id, plan: "swap it twice")
        at(LATER + 60_000)
        update(:pieces, id, plan: "swap it")

        assert_passes "pictures-fresh"
    end

    def test_a_piece_without_a_picture_is_never_stale
        piece(plan: "swap it")
        at(LATER)
        update(:pieces, 1, plan: "swap it twice")

        assert_passes "pictures-fresh"
    end

    def test_a_stale_item_fails_final
        update(:pieces, pictured, plan: "swap it twice")

        assert_fails "pictures-fresh",
                     "P1: plan changed after its last picture #{STAMP}",
                     final: true
    end
end

# pictures-fresh while a picture is redrawn, and in the write path.
class FreshRedrawTest < FreshCase
    REDRAWN = "P1: picture being redrawn (the new layout)"

    def compared
        Ledger::Checks.call(snapshot).select { it[0] == "pictures-fresh" }
    end

    # P1 verified, awaiting nothing yet, pictured at PLACED.
    def done
        pictured(status: "verified", verified_by: "me", evidence: "seen",
                 risk: "2/10 — small", risk_rating: 2)
    end

    def test_a_piece_being_redrawn_is_announced_and_fails_final
        update(:pieces, pictured, plan: "swap it twice",
                                  picture_pending: "the new layout")

        assert_equal ["pictures-fresh", true, REDRAWN],
                     report("pictures-fresh")
        assert_fails "pictures-fresh",
                     "P1: plan changed after its last picture #{STAMP}; " \
                     "#{REDRAWN}", final: true
    end

    def test_the_write_path_names_a_stale_piece_awaiting_a_finish
        id = done
        awaits(id, "commit")
        update(:pieces, id, plan: "swap it twice")

        assert_equal [["pictures-fresh", "P1 (awaits commit): plan changed " \
                                         "after its last picture #{STAMP} " \
                                         "— #{Ledger::Checks::Fresh::PAST}",
                       nil]], compared
    end

    def test_the_write_path_passes_a_piece_being_redrawn
        id = done
        awaits(id, "commit")
        update(:pieces, id, plan: "swap it twice",
                            picture_pending: "the new layout")

        assert_empty compared
    end

    def test_the_write_path_passes_a_stale_piece_awaiting_no_finish
        update(:pieces, done, plan: "swap it twice")

        assert_empty compared
    end
end

# pictures-fresh on open questions.
class FreshQuestionsTest < FreshCase
    def test_a_question_choice_added_after_its_picture_warns
        id = pictured_question
        choice(id, "C = keep both", 2)

        assert_equal "O1: choices changed after its last picture #{STAMP}",
                     report("pictures-fresh")[2]
    end

    def test_a_question_choice_dropped_or_reworded_warns
        pictured_question
        first, second = db[:question_choices].order(:id).select_map(:id)
        update(:question_choices, first, effect: "keep it longer")
        @rows.delete(:question_choices, second)

        assert_equal "O1: choices changed after its last picture #{STAMP}",
                     report("pictures-fresh")[2]
    end

    def test_a_question_detail_and_problem_warn_while_open
        id = pictured_question
        update(:questions, id, detail: "Which cache wins?", problem: "slow")

        assert_equal "O1: detail, problem changed after its last picture " \
                     "#{STAMP}", report("pictures-fresh")[2]
        update(:questions, id, closed_at: LATER)
        assert_passes "pictures-fresh", final: true
    end
end
