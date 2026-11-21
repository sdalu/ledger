# frozen_string_literal: true

require "fileutils"
require "json"

require "ledger/waker"
require "ledger/waker/bell"
require "ledger/waker/claude"
require "ledger/waker/scratch"
require "ledger/waker/trust"

module Ledger
    module Waker
        # `bin/ledger-waker --probe`: the line format tried on a scratch
        # session (Scratch) and, when it starts a turn there, recorded
        # with the Claude Code version (config/doorbell.json). The
        # session runs in one fixed directory the user trusts once; the
        # trust dialog is never answered here: an untrusted directory,
        # by ~/.claude.json or on the screen, is a refusal naming the
        # one step.
        class Probe
            DIR = "~/.cache/ledger-waker-probe"
            # The line the socket takes, its TEXT placeholder the doorbell.
            FORMAT = { "type" => "user",
                       "message" => { "role" => "user",
                                      "content" => TEXT } }.freeze
            ASK = "ledger-waker probe: reply with the single word pong"
            WAIT = 120

            # The probe's directory, not trusted yet.
            class Untrusted < Error; end

            def initialize(out: $stdout, claude: Claude.new, record: RECORD,
                           dir: File.expand_path(DIR),
                           trust: ->(dir) { Trust.of(dir) })
                @out = out
                @claude = claude
                @record = record
                @dir = dir
                @trust = trust
            end

            # -> 0 when the line started a turn and was recorded, 1 if
            # not, 2 refused (the directory is not trusted).
            def call
                FileUtils.mkdir_p(@dir)
                raise Untrusted if @trust.call(@dir) == :untrusted

                verdict = run(@claude.version)
                verdict ? failed(verdict) : 0
            rescue Untrusted
                @out.puts untrusted
                2
            ensure
                @scratch&.stop
            end

            def untrusted
                "probe: refused, Claude Code does not trust #{@dir} yet: " \
                    "start claude there once (cd #{@dir} && claude) and " \
                    "answer \"#{Trust::DIALOG}\"; nothing recorded"
            end

            private

            # -> nil when the scratch session took a turn on the line and
            # the record was written, else what went wrong.
            def run(version)
                @scratch = Scratch.new(@dir).tap(&:start)
                waited? { @scratch.stops >= 1 && !@scratch.socket.empty? } or
                    return "the scratch session never ended its first turn"
                failure = Bell.ring(@scratch.socket, Waker.line(ASK, FORMAT))
                return "the socket refused the line: #{failure}" if failure
                return "the line was written but no turn followed" unless
                    waited? { @scratch.stops >= 2 }

                recorded(version)
            end

            def recorded(version)
                write(version)
                @out.puts "probe: the line started a turn without the auth " \
                          "line; recorded for Claude Code #{version} in " \
                          "#{@record}"
                nil
            end

            # The scratch session's screen follows the verdict: what it
            # was showing says why (an error, a login).
            def failed(why)
                @out.puts "probe: FAILED, #{why}; nothing recorded"
                @scratch.screen.lines.map(&:rstrip).reject(&:empty?).last(15)
                        .each { @out.puts "  | #{it}" }
                1
            end

            # The record rewritten whole, through a temporary file renamed
            # into place; what else it holds (the measured facts) is kept.
            def write(version)
                kept = File.exist?(@record) ? Waker.record(@record) : {}
                body = kept.merge("claude_version" => version,
                                  "established" => Time.now.strftime("%F"),
                                  "auth" => "none", "line" => FORMAT)
                File.write("#{@record}.new", "#{JSON.pretty_generate(body)}\n")
                File.rename("#{@record}.new", @record)
            end

            # Whether the block held within WAIT seconds; the trust dialog
            # on the screen (a configuration the file did not show) is the
            # refusal.
            def waited?
                deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) +
                           WAIT
                until yield
                    raise Untrusted if @scratch.screen.include?(Trust::DIALOG)
                    return false if
                        Process.clock_gettime(Process::CLOCK_MONOTONIC) >
                        deadline

                    sleep 1
                end
                true
            end
        end
    end
end
