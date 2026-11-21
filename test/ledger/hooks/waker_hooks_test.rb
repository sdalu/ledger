# frozen_string_literal: true

require_relative "helper"
require "ledger/hooks/sessions"
require "ledger/hooks/stamp"

# What the hooks record for the waker: session-start the session, its
# socket path and its directory's ledgers; stamp each turn's end, run
# outside the bundle as the launcher runs it.
class WakerHooksTest < HookTest
    SOCKET = "/tmp/cc-socks/42.sock"

    def start(id = "s-1", env: { "CLAUDE_CODE_MESSAGING_SOCKET" => SOCKET })
        Ledger::Hooks::Sessions.record({ "session_id" => id, "cwd" => PLACE },
                                       env:, now: 5)
    end

    def test_session_start_records_the_session_and_its_ledgers
        start

        assert_equal [{ session_id: "s-1", socket: SOCKET, cwd: PLACE, at: 5 }],
                     db[:sessions].all
        assert_equal [[@ledger[:id]]],
                     db[:session_ledgers].select_map([:ledger_id])
    end

    def test_a_second_start_replaces_the_record
        start
        start(env: {})

        assert_nil db[:sessions].get(:socket)
        assert_equal 1, db[:session_ledgers].count
    end

    def test_a_directory_without_a_ledger_records_nothing
        Ledger::Hooks::Sessions.record({ "session_id" => "s-2",
                                         "cwd" => "/elsewhere" }, env: {})

        assert_empty db[:sessions].all
    end

    def test_the_hook_records_and_still_answers
        ENV["CLAUDE_CODE_MESSAGING_SOCKET"] = SOCKET
        hook("session-start", session_id: "s-3", source: "startup")

        assert_equal ["s-3"], db[:sessions].select_map(:session_id)
    ensure
        ENV.delete("CLAUDE_CODE_MESSAGING_SOCKET")
    end

    def test_stamp_records_the_turns_end_outside_the_bundle
        _out, err, status = launch("stamp", { session_id: "s-1", cwd: PLACE })

        assert_predicate status, :success?, err
        first = db[:session_stops].where(session_id: "s-1").get(:at)

        assert_operator first, :>, 0
        launch("stamp", { session_id: "s-1", cwd: PLACE })

        assert_equal 1, db[:session_stops].count
        assert_operator db[:session_stops].get(:at), :>=, first
    end

    def test_stamp_refuses_an_id_that_is_not_bare
        Ledger::Hooks::Stamp.call({ "session_id" => "x'); DROP TABLE x; --" })

        assert_empty db[:session_stops].all
    end
end
