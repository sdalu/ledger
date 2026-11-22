# frozen_string_literal: true

require "fileutils"
require "json"

module Ledger
    # What the waker needs in the user's Claude Code settings, merged in or
    # taken out (rake waker:install / waker:uninstall): the session-start
    # hook on SessionStart (left alone when a command already runs `ledger
    # hook session-start`, as the orchestration skill's ledger-hook.sh
    # does), the stamp hook on Stop, and crossSessionInbound accept. The
    # file is backed up beside itself first, written to a temporary file
    # and renamed, its mode kept; every other key and hook stays as it was.
    module WakerInstall
        GUARD = "command -v ledger >/dev/null 2>&1 || exit 0; exec ledger hook"
        HOOKS = {
            "SessionStart" => ["session-start",
                               "recording the session for the ledger waker"],
            "Stop" => ["stamp", "stamping the turn end for the ledger waker"]
        }.freeze
        INBOUND = "accept"
        PROBE = File.expand_path("~/.cache/ledger-waker-probe")

        module_function

        # -> the lines saying what changed, [] when nothing had to.
        def install(path)
            change(path) do |settings|
                HOOKS.filter_map { |event, spec| add(settings, event, *spec) } +
                    [inbound_on(settings)].compact
            end
        end

        # -> the lines saying what was taken out: the entries install adds
        # (by their status message) and crossSessionInbound when it is
        # accept; a hook the user or a skill installed stays.
        def uninstall(path)
            change(path) do |settings|
                HOOKS.filter_map { |ev, spec| remove(settings, ev, *spec) } +
                    [inbound_off(settings)].compact
            end
        end

        # The settings read, changed by the block, written when it said
        # something changed.
        def change(path)
            settings = JSON.parse(File.read(path))
            done = yield settings
            write(path, settings) unless done.empty?
            done
        end

        def add(settings, event, word, status)
            return if runs?(settings, event, word)

            ((settings["hooks"] ||= {})[event] ||= []) << entry(word, status)
            "#{event}: ledger hook #{word} added"
        end

        def remove(settings, event, word, status)
            list = settings.dig("hooks", event) or return
            kept = list.reject { ours?(it, status) }
            return if kept.size == list.size

            if kept.empty? then settings["hooks"].delete(event)
            else settings["hooks"][event] = kept
            end
            "#{event}: ledger hook #{word} removed"
        end

        def inbound_on(settings)
            return if settings["crossSessionInbound"] == INBOUND

            settings["crossSessionInbound"] = INBOUND
            "crossSessionInbound: #{INBOUND}"
        end

        def inbound_off(settings)
            return unless settings["crossSessionInbound"] == INBOUND

            settings.delete("crossSessionInbound")
            "crossSessionInbound: removed"
        end

        def entry(word, status)
            { "hooks" => [{ "type" => "command", "timeout" => 10,
                            "command" => "#{GUARD} #{word}",
                            "statusMessage" => status }] }
        end

        # A command of EVENT already runs `ledger hook WORD`, directly or
        # through a wrapper script that execs it.
        def runs?(settings, event, word)
            commands(settings, event).any? do |command|
                command.include?("ledger hook #{word}") ||
                    wrapper?(command, word)
            end
        end

        # The wrapper's path as the command writes it: bare, or in double
        # or single quotes, a leading ~ the home directory.
        def wrapper?(command, word)
            script = wrapper_path(command, word)
            script &&
                File.read(File.expand_path(script))
                    .include?('exec ledger hook "$1"')
        rescue SystemCallError
            false
        end

        def wrapper_path(command, word)
            found = %r{(?:"([^"]*/ledger-hook\.sh)"|'([^']*/ledger-hook\.sh)'|
                       ([^\s"']*/ledger-hook\.sh))\s+#{word}\b}x.match(command)
            found.captures.compact.first if found
        end

        def commands(settings, event)
            Array(settings.dig("hooks", event))
                .flat_map { Array(it["hooks"]) }.filter_map { it["command"] }
        end

        def ours?(group, status)
            Array(group["hooks"]).any? { it["statusMessage"] == status }
        end

        # A settings file that is a symlink is written where it points:
        # the rename would otherwise replace the link itself.
        def write(path, settings)
            path = File.realpath(path)
            mode = File.stat(path).mode
            FileUtils.cp(path, "#{path}.bak-waker", preserve: true)
            tmp = "#{path}.tmp#{Process.pid}"
            File.write(tmp, "#{JSON.pretty_generate(settings)}\n")
            File.chmod(mode, tmp)
            File.rename(tmp, path)
        end
    end
end
