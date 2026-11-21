# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "securerandom"
require "shellwords"

module Ledger
    module Waker
        # The probe's scratch session: an interactive `claude` (a
        # background one exits after its turn, its socket with it) under
        # a tmux server of its own, a throwaway session id, in DIR, whose
        # settings record the socket path (never the token), stamp each
        # turn's end and accept messages from outside; nothing of the
        # user's settings is read (--setting-sources local).
        class Scratch
            START = "Reply with the single word ready."
            FILES = %w[settings.json socket stops].freeze

            def initialize(dir)
                @dir = dir
                @server = "ledger-waker-probe-#{Process.pid}"
            end

            def start
                clear
                File.write(file("settings.json"),
                           JSON.pretty_generate(settings))
                system("tmux", "-L", @server, "new-session", "-d", "-s",
                       "probe", "-x", "160", "-y", "50", "-c", @dir,
                       command, exception: true)
            end

            def stop
                system("tmux", "-L", @server, "kill-server",
                       %i[out err] => File::NULL)
                clear
            end

            # How many turns ended, and the socket path its hook wrote.
            def stops = read("stops").lines.size
            def socket = read("socket").strip

            # What the session shows.
            def screen
                Open3.capture2e("tmux", "-L", @server, "capture-pane", "-p",
                                "-t", "probe").first
            end

            def clear = FILES.each { FileUtils.rm_f(file(it)) }

            private

            def command
                Shellwords.join(
                    ["claude", "--session-id", SecureRandom.uuid, "--settings",
                     file("settings.json"), "--setting-sources", "local",
                     "--model", "haiku", START]
                )
            end

            def settings
                socket = "printf '%s\\n' \"$CLAUDE_CODE_MESSAGING_SOCKET\" " \
                         "> #{Shellwords.escape(file("socket"))}"
                stop = "date +%s >> #{Shellwords.escape(file("stops"))}"
                { "crossSessionInbound" => "accept",
                  "hooks" => { "SessionStart" => [hook(socket)],
                               "Stop" => [hook(stop)] } }
            end

            def hook(command)
                { "hooks" => [{ "type" => "command", "command" => command }] }
            end

            def file(name) = File.join(@dir, name)

            def read(name)
                File.read(file(name))
            rescue Errno::ENOENT
                ""
            end
        end
    end
end
