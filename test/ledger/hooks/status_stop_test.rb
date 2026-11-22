# frozen_string_literal: true

require_relative "helper"

# status-stop: the status line is shown at a stop while a piece is out
# or back, once per distinct line for the session.
class StatusStopTest < HookTest
    ID = "sess-1"

    def stop(id: ID, **) = hook("status-stop", session_id: id, **)

    def shown(answer) = json(answer)["systemMessage"]

    def test_a_piece_out_shows_the_peek_line_and_exits_zero
        write("import") { piece(it, status: "out") }
        answer = stop

        assert_equal 0, answer.status
        assert_match(/\AStatus \(.*\) — .*out: P1/, shown(answer))
        assert_nil answer.err
    end

    def test_an_unchanged_line_is_shown_once_per_session
        write("import") { piece(it, status: "back") }

        refute_nil stop.out
        assert_equal Ledger::Hooks::Answer.pass, stop
        refute_nil stop(id: "sess-2").out
    end

    def test_a_changed_line_is_shown_again
        write("import") { piece(it, status: "out") }
        stop
        write("import") { piece(it, status: "back") }

        assert_match "back: P2", shown(stop)
    end

    def test_no_piece_out_or_back_and_no_ledger_say_nothing
        write("import") { piece(it, hold: "for the user") }

        assert_equal Ledger::Hooks::Answer.pass, stop
        assert_equal Ledger::Hooks::Answer.pass, stop(cwd: "/work/beta")
    end

    def test_a_session_id_that_is_not_bare_says_nothing
        write("import") { piece(it, status: "out") }

        assert_equal Ledger::Hooks::Answer.pass, stop(id: "../x")
        assert_equal Ledger::Hooks::Answer.pass, stop(id: "")
    end

    def test_a_ready_started_piece_sends_the_stop_back_naming_it
        write("import") { piece(it) }
        answer = stop

        assert_equal 2, answer.status
        assert_equal "ready and started, not sent: P1; send it or hold it " \
                     "with a reason (piece --hold)", answer.err
    end

    def test_the_stop_passes_once_the_piece_is_out
        id = nil
        write("import") { id = piece(it) }
        assert_equal 2, stop.status

        write("import") { it.status(id, "out", session: "s1") }

        assert_equal 0, stop.status
    end

    def test_a_held_piece_passes
        write("import") { piece(it, hold: "waits for the user") }

        assert_equal Ledger::Hooks::Answer.pass, stop
    end

    def test_a_piece_awaiting_its_start_passes
        write("import") do |change|
            id = piece(change)
            change.insert(:piece_awaits, piece_id: id, position: 0,
                                         word: "start")
        end

        assert_equal Ledger::Hooks::Answer.pass, stop
    end
end
