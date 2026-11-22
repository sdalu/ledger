# frozen_string_literal: true

require "ledger/hooks/journal_name"
require "ledger/hooks/launchers"
require "ledger/hooks/program_rules"
require "ledger/hooks/substitutions"
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
        # is the launcher passes, once no redirect of it names the journal;
        # nice, timeout, env, sudo and the like are read through, and
        # `$( )`, backticks and if/while/for bodies as commands. A launcher
        # option the table does not know is refused when the segment names
        # the journal. Standard library alone: it runs before
        # every Bash call.
        class JournalWrite
            COMMANDS = %w[piece ask answer word fact constraint decide noticed
                          criterion edit renumber choice mockup take undo
                          restore close].freeze
            SHELLS = %w[sh bash zsh dash].freeze
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

            # -> the journal word SEGMENT writes, or nil. A segment whose
            # launcher has an option the table does not know cannot be
            # told from a writer: it is refused when it names the journal.
            def writes(segment, depth = 0)
                redirected(segment) || command_write(segment, depth)
            end

            private

            def command_write(segment, depth)
                words = segment.map(&:text)
                at = Launchers.program_at(words)
                return unclassified(segment) unless at

                program = words[at] ? File.basename(words[at]) : ""
                return if launcher?(words, at, program)

                args = segment.drop(at + 1).reject { redirect?(it) }
                nested(program, args, depth) || @rules.call(program, args)
            end

            def unclassified(segment)
                segment.map(&:text).find { @name.match?(it) }
            end

            # A text read for substitutions first, then by segments; at
            # the depth limit it is refused when it names the journal.
            def first_write(text, depth)
                return @name.mentions(text).first if depth > DEPTH
                inner = Substitutions.in(text).lazy.filter_map do |part|
                    first_write(part, depth + 1)
                end
                inner.first || Words.segments(text).lazy
                                    .filter_map { writes(it, depth) }.first
            end

            def redirect?(word) = !word.quoted && ANY_REDIRECT.match?(word.text)

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
