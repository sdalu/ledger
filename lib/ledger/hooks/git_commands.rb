# frozen_string_literal: true

require "ledger/hooks/launchers"
require "ledger/hooks/substitutions"
require "ledger/hooks/words"

module Ledger
    module Hooks
        # The git commit, push and merge a shell command runs, read by
        # its words the way the journal-write hook reads them: past
        # nice, timeout, low-priority, env and the like, into `sh -c`
        # and `eval` text and `$( )` substitutions, past git's own
        # options (`-C DIR`, `-c K=V`, `--no-pager`).
        #
        #     GitCommands.in("nice git -C /r merge --ff-only feat")
        #     # => [#<data Call action="merge", args=["--ff-only", "feat"],
        #     #             dir="/r">]
        module GitCommands
            Call = Data.define(:action, :args, :dir)

            ACTIONS = %w[commit push merge].freeze
            SHELLS = %w[sh bash zsh dash].freeze
            OPTION_VALUE = %w[-C -c --git-dir --work-tree --namespace
                              --exec-path --super-prefix
                              --config-env].freeze
            REDIRECT = /\A\d*[<>]+[|&]?\z/
            DEPTH = 3

            module_function

            # -> the Calls of COMMAND, in the order they are written.
            def in(command, depth = 0)
                return [] if depth > DEPTH

                inner = Substitutions.in(command)
                                     .flat_map { self.in(it, depth + 1) }
                inner + Words.segments(command).flat_map { segment(it, depth) }
            end

            # A segment whose launcher has an option the table does not
            # know cannot be read: it yields nothing.
            def segment(segment, depth)
                words = segment.map(&:text)
                at = Launchers.program_at(words) or return []
                program = words[at] ? File.basename(words[at]) : ""
                args = segment.drop(at + 1).reject { redirect?(it) }
                return nested(program, args, depth) unless program == "git"

                [git(args.map(&:text))].compact
            end

            def redirect?(word) = !word.quoted && REDIRECT.match?(word.text)

            # `sh -c TEXT` and `eval TEXT`: the text read as commands.
            def nested(program, args, depth)
                texts = if SHELLS.include?(program) &&
                           args.any? { it.text == "-c" }
                            args.select(&:quoted).map(&:text)
                        elsif program == "eval"
                            [args.map(&:text).join(" ")]
                        else
                            []
                        end
                texts.flat_map { self.in(it, depth + 1) }
            end

            # The Call of the words after `git`, nil when the subcommand
            # is none of ACTIONS.
            def git(words)
                at = 0
                dir = nil
                while words[at]&.start_with?("-")
                    dir = words[at + 1] if words[at] == "-C"
                    at += OPTION_VALUE.include?(words[at]) ? 2 : 1
                end
                action = words[at]
                return unless ACTIONS.include?(action)

                Call.new(action:, args: words.drop(at + 1), dir:)
            end
        end
    end
end
