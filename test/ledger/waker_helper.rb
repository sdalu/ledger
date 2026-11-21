# frozen_string_literal: true

require "socket"

require_relative "helper"
require "ledger/inbox"
require "ledger/waker/pass"
require "ledger/waker/probe"

# The waker's pass on a journal of its own: the fixture ledger switched
# on, one session of its directory (s-idle) stamped eleven minutes ago,
# a fake socket it is recorded with, and a stubbed `claude` listing it
# idle.
class WakerCase < JournalTest
    Seen = Ledger::Waker::Claude::Seen
    Resumed = Ledger::Waker::Claude::Resumed
    IDLE = Seen.new(field: "status", word: "idle", short: nil)
    DONE = Seen.new(field: "state", word: "done", short: "aaaa1111")
    BUSY = Seen.new(field: "status", word: "busy", short: nil)
    MINUTE = 60_000
    NOW = 1_800_000_000_000
    TEXT = "ledger: an entry from the user waits on #{ADDRESS}; " \
           "run ledger inbox #{ADDRESS}".freeze

    # `claude` as the pass asks it: the sessions it lists, the resumes
    # it was asked for, the short id a resume answers.
    class FakeClaude
        attr_reader :resumed
        attr_accessor :listed, :short

        def initialize(listed = {})
            @listed = listed
            @resumed = []
        end

        def agents = @listed

        def resume(session_id, line, cwd)
            @resumed << [session_id, line, cwd]
            Resumed.new(short: @short || session_id[0, 8], failure: nil)
        end
    end

    def setup
        super
        # A short directory: a socket path has a length limit.
        @sockets = Dir.mktmpdir("lw", "/tmp")
        @server = UNIXServer.new(File.join(@sockets, "s.sock"))
        @claude = FakeClaude.new("s-idle" => IDLE)
        Ledger::Waker.switch(@journal, ADDRESS, true)
        session("s-idle", stop: NOW - (11 * MINUTE))
    end

    def teardown
        @server.close
        FileUtils.rm_rf(@sockets)
        super
    end

    def session(id, stop:)
        db[:sessions].insert(session_id: id, cwd: "/work/alpha", at: 0,
                             socket: File.join(@sockets, "s.sock"))
        db[:session_ledgers].insert(session_id: id,
                                    ledger_id: @ledger[:id])
        db[:session_stops].insert(session_id: id, at: stop)
    end

    def entry(text = "a word from the user", address: ADDRESS)
        Ledger::Inbox.append(@journal, address, [{ "text" => text }],
                             actor: "viewer:anna")
    end

    # The session's last turn ended MINUTES before NOW.
    def stopped(minutes, now: NOW)
        db[:session_stops].update(at: now - (minutes * MINUTE))
    end

    def pass(now = NOW)
        Ledger::Waker::Pass.new(@journal, claude: @claude,
                                          line: Ledger::Waker::Probe::FORMAT,
                                          idle_minutes: 10).call(now)
    end

    # The lines the fake socket received, one per connection.
    def received
        lines = []
        loop do
            client = @server.accept_nonblock
            lines << client.read
            client.close
        rescue IO::WaitReadable
            return lines
        end
    end

    def wakes = db[:wakes].order(:id).all
    def ways = wakes.map { it.values_at(:path, :outcome) }
end
