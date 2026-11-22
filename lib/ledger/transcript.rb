# frozen_string_literal: true

require "json"
require "time"

require "ledger/text/fold"

module Ledger
    # The transcript of the session running a command: the JSONL file
    # Claude Code keeps at <config>/projects/<cwd as dashes>/<session
    # id>.jsonl, the config directory being $CLAUDE_CONFIG_DIR or
    # ~/.claude. A session started in one directory keeps its transcript
    # there even when its commands run in a worktree, so every project
    # directory is searched when the one the cwd names lacks it. Read
    # only; nil when no session id is set or no file is found.
    #
    #     transcript = Ledger::Transcript.current
    #     transcript&.heard_since?(ms)         # => true
    #     transcript&.quoted?("keep it short") # => false
    class Transcript
        # The opening of a message the user did not type, in a transcript
        # written before records carried their origin: a peer session, a
        # delegate's notification, a reminder, an interruption, a
        # summary of a compacted context, a slash command's echo.
        RELAYED = /\A\s*(?:<(?:system-reminder|task-notification|
                                local-command|command-name)
                          |Another\ Claude\ session
                          |\[Request\ interrupted
                          |This\ session\ is\ being\ continued)/x
        # A reminder appended inside a message the user typed.
        REMINDER = %r{<system-reminder>.*?</system-reminder>}m

        def self.current(env: ENV, cwd: Dir.pwd)
            id = env["CLAUDE_CODE_SESSION_ID"].to_s
            return if id.empty? || id.include?("/")

            path = locate(projects(env), cwd, id)
            new(path) if path
        end

        def self.projects(env)
            config = env["CLAUDE_CONFIG_DIR"].to_s
            config = File.join(Dir.home, ".claude") if config.empty?
            File.join(config, "projects")
        end

        def self.locate(projects, cwd, id)
            name = "#{id}.jsonl"
            own = File.join(projects, cwd.gsub(/[^A-Za-z0-9]/, "-"), name)
            return own if File.file?(own)

            Dir.glob(File.join(projects, "*", name)).find { File.file?(it) }
        end

        attr_reader :path

        def initialize(path)
            @path = path
        end

        # [[ms, text]] of the messages the user typed, in file order.
        def messages
            @messages ||= File.foreach(@path).filter_map do |line|
                record = parse(line)
                [time(record), text(record)] if record && human?(record)
            end
        end

        # Whether the user wrote a message after MS (epoch milliseconds).
        def heard_since?(ms) = messages.any? { |at, _| at > ms }

        # Whether QUOTE, folded, stands in one of the user's messages.
        def quoted?(quote)
            folded = Text::Fold.fold(quote)
            return false if folded.empty?

            messages.any? { |_, text| Text::Fold.fold(text).include?(folded) }
        end

        private

        def parse(line)
            record = JSON.parse(line)
            record if record.is_a?(Hash)
        rescue JSON::ParserError
            nil
        end

        # A record the user typed: type user, none of the marks of a
        # reminder, a delegate's thread or a summary, no tool result,
        # and an origin of kind human (or, with no origin, a text that
        # opens as no relayed message does).
        def human?(record)
            return false unless record["type"] == "user" &&
                                plain?(record) && !tool_result?(record)

            origin = record["origin"]
            return origin["kind"] == "human" if origin.is_a?(Hash)

            !RELAYED.match?(raw(record))
        end

        def plain?(record)
            %w[isMeta isSidechain isCompactSummary].none? { record[it] }
        end

        def tool_result?(record)
            content = record.dig("message", "content")
            content.is_a?(Array) &&
                content.any? { it.is_a?(Hash) && it["type"] == "tool_result" }
        end

        def raw(record)
            content = record.dig("message", "content")
            return content.to_s unless content.is_a?(Array)

            content.filter_map { it["text"] if it.is_a?(Hash) }.join("\n")
        end

        def text(record) = raw(record).gsub(REMINDER, " ")

        def time(record)
            (Time.iso8601(record["timestamp"].to_s).to_r * 1000).to_i
        rescue ArgumentError
            0
        end
    end
end
