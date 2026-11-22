# frozen_string_literal: true

require "stringio"

require_relative "waker_helper"
require "ledger/waker/main"

# The forever loop against a stub `claude` program: the first
# `claude agents` fails, the second warns on stderr and lists, the third
# lists; the loop runs three passes, sleeps between them, and the third
# acts. Nothing the stub prints on stderr is read as the listing.
class WakerLoopTest < WakerCase
    STUB = <<~SH
        #!/bin/sh
        case "$1" in
        --version) echo "2.1.329" ;;
        agents)
            n=$(cat "$COUNT" 2>/dev/null || echo 0)
            n=$((n + 1))
            echo "$n" > "$COUNT"
            case $n in
            1) echo "boom: service down" >&2; exit 1 ;;
            2) echo "warning: update available" >&2 ;;
            esac
            echo '[{"sessionId":"s-idle","status":"idle","pid":1}]'
            ;;
        esac
    SH

    def setup
        super
        @count = File.join(@dir, "count")
        @program = File.join(@dir, "claude")
        File.write(@program, STUB.gsub("$COUNT", @count))
        File.chmod(0o755, @program)
        db[:session_stops].update(at: Ledger::Write.now - (11 * MINUTE))
        entry
        record
    end

    def record
        @record = File.join(@dir, "doorbell.json")
        File.write(@record, JSON.generate(
                                "claude_version" => "2.1.329",
                                "line" => Ledger::Waker::Probe::FORMAT
                            ))
    end

    # A sleeper that notes each sleep and interrupts the third.
    def sleeper(sleeps)
        lambda do |seconds|
            sleeps << seconds
            raise Interrupt if sleeps.size == 3
        end
    end

    # The forever loop until its third sleep: [status, out, err, sleeps].
    def run_loop
        out = StringIO.new
        err = StringIO.new
        sleeps = []
        claude = Ledger::Waker::Claude.new(
            program: @program, log: ->(line) { err.puts(line) }
        )
        main = Ledger::Waker::Main.new(out:, err:, record: @record, claude:,
                                       sleeper: sleeper(sleeps))
        [main.run([]), out.string, err.string, sleeps]
    end

    def test_a_failed_then_warned_then_good_call_keeps_the_loop_going
        status, out, err, sleeps = run_loop

        assert_equal [0, [60, 60, 60]], [status, sleeps]
        assert_equal "3", File.read(@count).strip
        assert_includes err, "claude agents: boom: service down"
        assert_includes err, "warning: update available"
        assert_equal 1, out.lines.size
        assert_includes out, "wake s-idle"
        assert_equal [%w[socket posted]], ways
    end
end

# The agents call itself: stderr kept apart, a failure or an unparsable
# listing raised as Failed.
class WakerAgentsTest < Minitest::Test
    Claude = Ledger::Waker::Claude

    def claude(output, ok: true, error: "")
        @logged = []
        Claude.new(run: ->(_argv, _dir) { [output, ok, error] },
                   log: ->(line) { @logged << line })
    end

    def test_stderr_is_logged_not_parsed
        seen = claude("[]", error: "warning: x\n").agents

        assert_empty seen
        assert_equal ["claude: warning: x"], @logged
    end

    def test_a_failed_call_names_its_reason
        error = assert_raises(Claude::Failed) do
            claude("", ok: false, error: "boom\n").agents
        end

        assert_equal "claude agents: boom", error.message
    end

    def test_output_that_is_no_listing_fails
        ["not json", "{}", "[1]"].each do |output|
            assert_raises(Claude::Failed, output) { claude(output).agents }
        end
    end
end
