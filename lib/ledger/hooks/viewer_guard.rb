# frozen_string_literal: true

require "ledger/hooks/launchers"
require "ledger/hooks/substitutions"
require "ledger/hooks/words"

module Ledger
    module Hooks
        # PreToolUse on Bash: a command that starts or stops the viewer or
        # the waker is refused. The user owns their lifecycle; a session
        # restarts the viewer in place (`rake server:restart`). The
        # command is read by its words, as journal-write reads it: past
        # nice, timeout, low-priority, env, nohup and the like, past
        # `bundle exec`, into `sh -c` and `eval` text and `$( )`
        # substitutions. A word that only names the program (an argument
        # of grep, an echo) is no start. A segment whose launcher has an
        # option the table does not know cannot be read and passes.
        # Standard library alone: it runs before every Bash call.
        module ViewerGuard
            PROGRAMS = %w[ledger-viewer ledger-waker].freeze
            TASKS = %w[server:start server:stop].freeze
            SHELLS = %w[sh bash zsh dash].freeze
            BUNDLERS = %w[bundle bundler].freeze
            REDIRECT = /\A\d*[<>]+[|&]?\z/
            DEPTH = 3
            REASON = "Refused: the user starts and stops the viewer; a " \
                     "session only restarts it in place " \
                     "(rake server:restart)."

            module_function

            def call(payload)
                return Answer.pass unless payload["tool_name"] == "Bash"

                input = payload["tool_input"]
                command = input.is_a?(Hash) ? input["command"].to_s : ""
                return Answer.pass unless starts_or_stops?(command, 0)

                Answer.json(deny)
            end

            def deny
                { hookSpecificOutput: {
                    hookEventName: "PreToolUse", permissionDecision: "deny",
                    permissionDecisionReason: REASON
                } }
            end

            def starts_or_stops?(text, depth)
                return false if depth > DEPTH

                inner = Substitutions.in(text)
                inner.any? { starts_or_stops?(it, depth + 1) } ||
                    Words.segments(text).any? { segment?(it, depth) }
            end

            def segment?(segment, depth)
                words = segment.map(&:text)
                at = Launchers.program_at(words) or return false
                program = words[at] ? File.basename(words[at]) : ""
                args = segment.drop(at + 1).reject { redirect?(it) }
                return true if PROGRAMS.include?(program)

                texts(program, args).any? { starts_or_stops?(it, depth + 1) }
            end

            def redirect?(word) = !word.quoted && REDIRECT.match?(word.text)

            # The command text a program runs: `rake TASK` (read as the
            # viewer's own name), `bundle exec CMD`, `sh -c TEXT` and
            # `eval TEXT`.
            def texts(program, args)
                words = args.map(&:text)
                return rake(words) if program == "rake"
                return bundled(words) if BUNDLERS.include?(program)
                return shell_text(args) if SHELLS.include?(program)

                program == "eval" ? [words.join(" ")] : []
            end

            def rake(words) = TASKS.intersect?(words) ? ["ledger-viewer"] : []

            def bundled(words)
                words.first == "exec" ? [words.drop(1).join(" ")] : []
            end

            def shell_text(args)
                return [] unless args.any? { it.text == "-c" }

                args.select(&:quoted).map(&:text)
            end
        end
    end
end
