# frozen_string_literal: true

require "json"
require "open3"

module Ledger
    module Waker
        # What the waker asks of the installed Claude Code: its version,
        # its sessions (`claude agents --json --all`) and a resume in the
        # background. RUN is how a command runs, [argv, chdir] -> [stdout,
        # success, stderr]; a test hands its own. Stderr is logged, never
        # read as the answer.
        class Claude
            # `claude agents` gave no listing this time: the loop goes on
            # with its next pass.
            class Failed < Ledger::Error; end

            # A session as `claude agents` lists it: an interactive one
            # carries `status` (idle, busy), a background one `state`
            # (done, working, blocked, failed); `short` is its short id.
            Seen = Data.define(:field, :word, :short) do
                # Idle for the waker: listed idle, or a background done.
                def idle?
                    [%w[status idle], %w[state done]].include?([field, word])
                end

                # A live process: only the socket may reach it.
                def live? = field == "status"
            end

            # What a resume answered: the short id it backgrounded, or
            # the reason it failed.
            Resumed = Data.define(:short, :failure)

            BACKGROUNDED = /^backgrounded\s+\S+\s+(\h+)\s*$/
            SYSTEM = lambda do |argv, chdir|
                options = chdir ? { chdir: } : {}
                output, error, status = Open3.capture3(*argv, **options)
                [output, status.success?, error]
            rescue SystemCallError => e
                ["", false, e.message]
            end
            LOG = ->(line) { warn("ledger-waker: #{line}") }

            def initialize(program: "claude", run: SYSTEM, log: LOG)
                @program = program
                @run = run
                @log = log
            end

            # "2.1.329", the first word `claude --version` prints.
            def version
                output, ok, error = @run.call([@program, "--version"], nil)
                unless ok
                    raise Refused, "claude --version: " \
                                   "#{reason(output, error)}"
                end

                output.split.first.to_s
            end

            # sessionId => Seen, every session `claude agents` lists;
            # Failed, with the reason, when the call fails or its output
            # is no listing.
            def agents
                output, ok, error = @run.call(
                    [@program, "agents", "--json", "--all"], nil
                )
                logged(error)
                raise Failed, "claude agents: #{reason(output, error)}" unless
                    ok

                listing(output)
            end

            # `claude --resume ID --bg LINE` in CWD, no other flag: flags
            # would start a copy under a new id rather than continue it.
            def resume(session_id, line, cwd)
                argv = [@program, "--resume", session_id, "--bg", line]
                output, ok, error = @run.call(argv, cwd)
                logged(error)
                short = output[BACKGROUNDED, 1]
                return Resumed.new(short:, failure: nil) if ok && short

                Resumed.new(short: nil, failure: reason(output, error))
            end

            private

            def listing(output)
                rows = JSON.parse(output)
                unless rows.is_a?(Array) && rows.all?(Hash)
                    raise Failed, "claude agents: not a list of sessions"
                end

                rows.to_h { [it["sessionId"], seen(it)] }
            rescue JSON::ParserError => e
                raise Failed, "claude agents: not JSON (#{e.message[0, 60]})"
            end

            def logged(error)
                text = error.to_s.strip
                @log.call("claude: #{text}") unless text.empty?
            end

            def reason(output, error)
                last_line(error.to_s.strip.empty? ? output : error)
            end

            def seen(row)
                field = row.key?("status") ? "status" : "state"
                Seen.new(field:, word: row[field].to_s, short: row["id"])
            end

            def last_line(output)
                output.lines.map(&:strip).reject(&:empty?).last ||
                    "no output"
            end
        end
    end
end
