# frozen_string_literal: true

require "json"
require "open3"

module Ledger
    module Waker
        # What the waker asks of the installed Claude Code: its version,
        # its sessions (`claude agents --json --all`) and a resume in the
        # background. RUN is how a command runs, [argv, chdir] -> [output,
        # success]; a test hands its own.
        class Claude
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
                output, status = Open3.capture2e(*argv, **options)
                [output, status.success?]
            rescue SystemCallError => e
                [e.message, false]
            end

            def initialize(program: "claude", run: SYSTEM)
                @program = program
                @run = run
            end

            # "2.1.329", the first word `claude --version` prints.
            def version
                output, ok = @run.call([@program, "--version"], nil)
                raise Refused, "claude --version: #{output.strip}" unless ok

                output.split.first.to_s
            end

            # sessionId => Seen, every session `claude agents` lists.
            def agents
                output, ok = @run.call([@program, "agents", "--json", "--all"],
                                       nil)
                raise Refused, "claude agents: #{output.strip}" unless ok

                JSON.parse(output).to_h { [it["sessionId"], seen(it)] }
            end

            # `claude --resume ID --bg LINE` in CWD, no other flag: flags
            # would start a copy under a new id rather than continue it.
            def resume(session_id, line, cwd)
                argv = [@program, "--resume", session_id, "--bg", line]
                output, ok = @run.call(argv, cwd)
                short = output[BACKGROUNDED, 1]
                return Resumed.new(short:, failure: nil) if ok && short

                Resumed.new(short: nil, failure: last_line(output))
            end

            private

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
