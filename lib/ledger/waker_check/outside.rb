# frozen_string_literal: true

require "json"

require "ledger/waker"
require "ledger/waker/claude"
require "ledger/waker_install"

module Ledger
    class WakerCheck
        # The two conditions that read files rather than the journal:
        # each answers `lines`, [state, name, detail] rows of :ok or :warn.

        # The installed Claude Code is the one the doorbell format was
        # established on (config/doorbell.json). VERSION is how the
        # installed one is asked; a test hands its own.
        class Version
            ASK = -> { Waker::Claude.new.version }

            def initialize(record: Waker::RECORD, ask: ASK)
                @record = record
                @ask = ask
            end

            def lines
                recorded = JSON.parse(File.read(@record))["claude_version"]
                installed = @ask.call
                return [[:ok, "claude", "#{installed}, as recorded"]] if
                    installed == recorded

                [[:warn, "claude", "Claude Code is #{installed}, the " \
                                   "doorbell format was established on " \
                                   "#{recorded}"]]
            rescue Ledger::Error, SystemCallError, JSON::ParserError => e
                [[:warn, "claude", e.message.lines.first.to_s.strip]]
            end
        end

        # The hooks and crossSessionInbound `rake waker:install` adds are
        # in the settings file.
        class Settings
            def initialize(path)
                @path = path
            end

            def lines
                missing = lacking(JSON.parse(File.read(@path)))
                if missing.empty?
                    return [[:ok, "settings",
                             "hooks and crossSessionInbound present"]]
                end

                [[:warn, "settings", "#{@path} lacks #{missing.join(", ")}: " \
                                     "rake waker:install"]]
            rescue SystemCallError, JSON::ParserError => e
                [[:warn, "settings", "#{@path}: #{e.class}"]]
            end

            private

            def lacking(data)
                missing = WakerInstall::HOOKS.filter_map do |event, (word, _)|
                    "#{event} hook #{word}" unless
                        WakerInstall.runs?(data, event, word)
                end
                missing << "crossSessionInbound" unless
                    data["crossSessionInbound"] == WakerInstall::INBOUND
                missing
            end
        end
    end
end
