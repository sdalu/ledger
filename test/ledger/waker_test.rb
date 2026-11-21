# frozen_string_literal: true

require_relative "waker_helper"

# A wake: one line on the socket, once per idle spell, within the
# budget of two an hour and eight a day.
class WakerOnceTest < WakerCase
    def test_a_wake_happens_once
        entry
        entry("a second word")

        assert_equal 1, pass.size
        assert_equal({ "type" => "user",
                       "message" => { "role" => "user", "content" => TEXT } },
                     JSON.parse(received.first))
        assert_equal [%w[socket posted]], ways
    end

    def test_no_second_wake_before_the_session_stops_again
        entry
        pass
        received

        assert_empty pass(NOW + MINUTE)
        assert_empty received
    end

    def test_the_budget_stops_further_wakes
        entry
        3.times do |part|
            now = NOW + (part * 20 * MINUTE)
            stopped(11, now:)
            pass(now)
        end

        assert_equal 2, wakes.size, "two an hour"
        assert_equal 2, received.size
    end

    def test_the_day_budget_holds_past_the_hour
        entry
        12.times do |n|
            now = NOW + (n * 61 * MINUTE)
            stopped(11, now:)
            pass(now)
        end

        assert_equal 8, wakes.size
    end

    def test_one_doorbell_names_every_ledger_of_the_session
        other = second_ledger
        entry
        entry("x", address: other)
        pass
        content = JSON.parse(received.first).dig("message", "content")

        assert_equal "ledger: an entry from the user waits on #{ADDRESS}, " \
                     "#{other}; run ledger inbox #{ADDRESS}, ledger inbox " \
                     "#{other}", content
        assert_equal 2, wakes.size
    end

    # LEDGER-web.md beside the fixture, switched on, of s-idle too.
    def second_ledger
        other = "/work/alpha/LEDGER-web.md"
        @journal.create_ledger(other, project: "alpha")
        Ledger::Write.run(@journal, other, "new", []) { nil }
        Ledger::Waker.switch(@journal, other, true)
        db[:session_ledgers].insert(session_id: "s-idle",
                                    ledger_id: @journal.ledger(other)[:id])
        other
    end
end

# What never wakes.
class WakerNeverTest < WakerCase
    def test_a_ledger_switched_off_never_wakes
        Ledger::Waker.switch(@journal, ADDRESS, false)
        entry

        assert_empty pass
        assert_empty wakes
        assert_empty received
    end

    def test_a_stall_never_wakes
        write { piece(it, status: "out") }

        assert_empty pass(NOW + (24 * 60 * MINUTE))
        assert_empty wakes
    end

    def test_a_session_idle_too_short_a_while_is_left
        entry
        stopped(5)

        assert_empty pass
    end

    def test_a_busy_session_is_left
        entry
        @claude.listed = { "s-idle" => BUSY }

        assert_empty pass
        assert_empty @claude.resumed
    end

    def test_a_session_never_stamped_is_left
        db[:session_stops].delete
        entry

        assert_empty pass
    end

    def test_a_live_session_whose_socket_is_gone_is_never_resumed
        @server.close
        File.unlink(File.join(@sockets, "s.sock"))
        entry
        pass

        assert_empty @claude.resumed
        assert_equal "socket", wakes.first[:path]
        assert_match(/\Afailed: /, wakes.first[:outcome])
    end
end

# The resume: a session not listed, or a background one done.
class WakerResumeTest < WakerCase
    def test_a_session_not_listed_is_resumed_in_its_directory
        @claude.listed = {}
        entry
        pass

        assert_equal [["s-idle", TEXT, "/work/alpha"]], @claude.resumed
        assert_equal [%w[resume resumed]], ways
        assert_empty received, "an exited session's socket is not written"
    end

    def test_a_background_session_done_is_resumed
        @claude.listed = { "s-idle" => DONE }
        entry
        pass

        assert_equal 1, @claude.resumed.size
    end

    def test_a_copy_moves_the_session_to_its_id
        copying
        entry
        pass

        assert_equal "copied c0ffee00-1111", wakes.first[:outcome]
        assert_equal ["c0ffee00-1111"], db[:sessions].select_map(:session_id)
        assert_equal ["c0ffee00-1111"],
                     db[:session_ledgers].select_map(:session_id)
    end

    # A resume answers a copy, c0ffee00, listed once it has run.
    def copying
        @claude.short = "c0ffee00"
        @claude.listed = {}
        @claude.define_singleton_method(:agents) do
            resumed.empty? ? {} : { "c0ffee00-1111" => DONE }
        end
    end
end

# What the waker reads of `claude`: the listing, a resume's answer.
class WakerClaudeTest < Minitest::Test
    LISTED = [{ "sessionId" => "a", "status" => "idle", "pid" => 1 },
              { "sessionId" => "b", "status" => "busy", "pid" => 2 },
              { "sessionId" => "c", "id" => "c", "state" => "done" },
              { "sessionId" => "d", "id" => "d", "state" => "blocked" }]
             .freeze

    def claude(output, ok: true)
        @calls = []
        run = lambda do |argv, chdir|
            @calls << [argv, chdir]
            [output, ok]
        end
        Ledger::Waker::Claude.new(run:)
    end

    def test_the_listing_tells_idle_from_busy_and_done
        seen = claude(JSON.generate(LISTED)).agents

        assert_equal [true, false, true, false], seen.values.map(&:idle?)
        assert_equal [true, true, false, false], seen.values.map(&:live?)
    end

    def test_a_resume_passes_no_flag_and_reads_the_short_id
        resumed = claude("Starting background service…\nnote: woke " \
                         "session c630aeb2\nbackgrounded · c630aeb2\n")
                  .resume("c630aeb2-3a28", "the line", "/work")

        assert_equal "c630aeb2", resumed.short
        assert_equal [[%w[claude --resume c630aeb2-3a28 --bg] + ["the line"],
                       "/work"]], @calls
    end

    def test_a_failed_resume_says_why
        resumed = claude("error: no such session\n", ok: false)
                  .resume("x", "the line", "/work")

        assert_nil resumed.short
        assert_equal "error: no such session", resumed.failure
    end
end
