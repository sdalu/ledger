# frozen_string_literal: true

require "ledger"
require "ledger/waker"
require "ledger/waker/claude"
require "ledger/waker/pass"
require "ledger/waker/probe"

module Ledger
    module Waker
        # `bin/ledger-waker [--once | --probe]`: the foreground loop, a
        # pass a minute until interrupted; --once makes one pass; --probe
        # establishes the line format again on a scratch session. The loop
        # refuses to start when the installed Claude Code is not the
        # version the format was established on. Exit status: 0 done,
        # 1 a probe that failed, 2 a refusal.
        class Main
            USAGE = "usage: ledger-waker [--once | --probe]"
            EVERY = 60

            def self.run(argv, out: $stdout, err: $stderr)
                new(out:, err:).run(argv)
            end

            def initialize(out:, err:, claude: nil, record: RECORD,
                           sleeper: Kernel.method(:sleep))
                @out = out
                @err = err
                @claude = claude || Claude.new(log: method(:log))
                @record = record
                @sleeper = sleeper
            end

            def run(argv)
                case argv
                in [] then watch(forever: true)
                in ["--once"] then watch(forever: false)
                in ["--probe"] then Probe.new(out: @out, claude: @claude,
                                              record: @record).call
                in ["-h" | "--help"] then help
                else refuse(USAGE)
                end
            rescue Refused => e
                refuse(e.message)
            end

            private

            # The format checked before the journal is opened: a refusal
            # touches nothing.
            def watch(forever:)
                line = established!
                journal = Journal.open
                cycle(Pass.new(journal, claude: @claude, line:), forever)
            rescue Interrupt
                0
            ensure
                journal&.close
            end

            def cycle(pass, forever)
                loop do
                    once(pass)
                    break unless forever

                    @sleeper.call(EVERY)
                end
                0
            end

            # One pass; a failed `claude agents` is logged and the pass
            # ends, the next one a minute on.
            def once(pass)
                pass.call.each { @out.puts said(it) }
                @out.flush
            rescue Claude::Failed => e
                log(e.message)
            end

            def log(message) = @err.puts("ledger-waker: #{message}")

            # The record's line, refused when Claude Code is not the
            # version it was established on.
            def established!
                record = Waker.record(@record)
                recorded = record["claude_version"]
                unless recorded && record["line"]
                    raise Refused, "#{@record} records no established " \
                                   "format: run bin/ledger-waker --probe"
                end
                same!(@claude.version, recorded)
                record["line"]
            end

            def same!(installed, recorded)
                return if installed == recorded

                raise Refused, "Claude Code is #{installed}, the doorbell " \
                               "format was established on #{recorded}: " \
                               "run bin/ledger-waker --probe"
            end

            def said(wake)
                ledgers = wake.ledger_ids.map { "L#{it}" }.join(", ")
                "#{Time.now.strftime("%F %T")} wake #{wake.session_id} " \
                    "(#{ledgers}) #{wake.path}: #{wake.outcome}"
            end

            def help
                @out.puts USAGE
                0
            end

            def refuse(message)
                log(message)
                2
            end
        end
    end
end
