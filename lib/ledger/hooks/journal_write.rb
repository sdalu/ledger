# frozen_string_literal: true

require "ledger/hooks/journal_name"
require "ledger/hooks/program_rules"
require "ledger/hooks/words"

module Ledger
    module Hooks
        # PreToolUse on Bash: a command that writes the journal by hand is
        # refused, naming the bin/ledger commands to use. A hand write
        # skips the write path: the checks a write must pass and the
        # events undo and restore read. By the words of the command (the
        # journal's own method): a redirect into
        # the journal or a companion, then ProgramRules per segment; `sh
        # -c` and `eval` text is read as commands. A segment whose program
        # is the launcher passes. Standard library alone: it runs before
        # every Bash call.
        class JournalWrite
            COMMANDS = %w[piece ask answer word fact constraint decide noticed
                          criterion edit renumber choice mockup take undo
                          restore close].freeze
            SHELLS = %w[sh bash zsh dash].freeze
            PREFIXES = %w[env nice command exec sudo].freeze
            ASSIGNMENT = /\A\w+=/
            REDIRECT = /\A\d*>+\|?\z/
            ANY_REDIRECT = /\A\d*[<>]+[|&]?\z/
            DEPTH = 3

            def self.call(payload)
                return Answer.pass unless payload["tool_name"] == "Bash"
                input = payload["tool_input"]
                command = input.is_a?(Hash) ? input["command"].to_s : ""
                hit = new(JournalName.current).refusal(command)
                hit ? Answer.json(deny(hit)) : Answer.pass
            end

            def self.deny(hit)
                { hookSpecificOutput: {
                    hookEventName: "PreToolUse", permissionDecision: "deny",
                    permissionDecisionReason: reason(hit)
                } }
            end

            def self.reason(hit)
                "Refused: this command writes the orchestration journal " \
                    "#{hit} by hand, skipping the write path: the checks a " \
                    "write must pass and the events undo and restore read. " \
                    "Use bin/ledger (orchestration): " \
                    "#{COMMANDS.map { "`#{it}`" }.join(", ")}; to read it, " \
                    "`bin/ledger show ADDRESS` or `sqlite3 -readonly`."
            end

            def initialize(name)
                @name = name
                @rules = ProgramRules.new(name)
            end

            # -> the journal word the first writing segment names, or nil.
            def refusal(command)
                return unless @name.mentioned?(command)
                first_write(command, 0)
            end

            # -> the journal word SEGMENT writes, or nil.
            def writes(segment, depth = 0)
                words = segment.map(&:text)
                at, program = program(words)
                return if launcher?(words, at, program)

                args = segment.drop(at + 1).reject { redirect?(it) }
                redirected(segment) || nested(program, args, depth) ||
                    @rules.call(program, args)
            end

            private

            def first_write(text, depth)
                Words.segments(text).lazy.filter_map { writes(it, depth) }
                     .first
            end

            def redirect?(word) = !word.quoted && ANY_REDIRECT.match?(word.text)

            # -> [index of the program word, its basename], past variable
            # assignments and a prefix (env, nice, exec, sudo).
            def program(words)
                at = words.index { |word| !prefix?(word) } || words.size
                [at, words[at] ? File.basename(words[at]) : ""]
            end

            def prefix?(word)
                ASSIGNMENT.match?(word) || PREFIXES.include?(word)
            end

            # bin/ledger, or `sh bin/ledger`: the sanctioned writer.
            def launcher?(words, at, program)
                return true if program == "ledger"
                SHELLS.include?(program) && !words[at + 1].nil? &&
                    File.basename(words[at + 1]) == "ledger"
            end

            def redirected(segment)
                pair = segment.each_cons(2).find do |op, target|
                    !op.quoted && REDIRECT.match?(op.text) &&
                        @name.match?(target.text)
                end
                pair&.last&.text
            end

            # `sh -c TEXT` and `eval TEXT`: the text read as commands.
            def nested(program, args, depth)
                return if depth >= DEPTH
                nested_texts(program, args).lazy
                                           .filter_map do |text|
                    first_write(text, depth + 1)
                end.first
            end

            def nested_texts(program, args)
                if SHELLS.include?(program) && args.any? { it.text == "-c" }
                    args.select { it.quoted && it.text.size > 3 }.map(&:text)
                elsif program == "eval"
                    [args.map(&:text).join(" ")]
                else
                    []
                end
            end
        end
    end
end
