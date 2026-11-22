# frozen_string_literal: true

require "open3"

require "ledger/commit_word"
require "ledger/hooks/git_commands"
require "ledger/hooks/ledgers"
require "ledger/hooks/push_word"

module Ledger
    module Hooks
        # PreToolUse on Bash, in the main session only (a payload with an
        # agent_id is a delegate's): a git commit, merge or push in a
        # repository whose project has a live ledger is refused unless
        # the user's word is on file for it.
        #
        # - commit and merge: some piece was given its commit word and
        #   holds no commit yet (that word is unspent). A merge with
        #   nothing to land, HEAD..BRANCH empty, passes.
        # - push: some piece was given its push word after the last push
        #   this hook let through for the repository (PushWord); an
        #   allowed push records the time.
        #
        # No live ledger, a delegate, or any other command passes
        # silently.
        module WordGate
            GIT = /\bgit\b/
            ENDS = %w[--abort --continue --quit].freeze
            OPTION_VALUE = %w[-m -s -X -F --into-name].freeze

            module_function

            def call(payload)
                command = command(payload)
                return Answer.pass unless payload["tool_name"] == "Bash" &&
                                          payload["agent_id"].to_s.empty? &&
                                          GIT.match?(command)

                GitCommands.in(command).each do |call|
                    reason = refusal(payload, call)
                    return Answer.json(deny(reason)) if reason
                end
                Answer.pass
            end

            def command(payload)
                input = payload["tool_input"]
                input.is_a?(Hash) ? input["command"].to_s : ""
            end

            # -> why CALL may not go, nil when it may.
            def refusal(payload, call)
                dir = File.expand_path(call.dir.to_s, cwd(payload))
                found = Ledgers.read(payload.merge("cwd" => dir))
                return if found.empty?

                case call.action
                when "commit" then unspent(found, "commit")
                when "merge" then merging(found, call, dir)
                else pushed(found, dir)
                end
            end

            def merging(found, call, dir)
                unspent(found, "merge") if landing?(call, dir)
            end

            def cwd(payload)
                payload["cwd"].to_s.empty? ? Dir.pwd : payload["cwd"].to_s
            end

            def unspent(found, action)
                open = given(found).any? do |ledger, piece|
                    ledger.derive.commits(piece).empty?
                end
                return if open

                "git #{action} needs the user's commit word: no piece of " \
                    "#{found.map(&:address).join(", ")} was given one " \
                    "that holds no commit yet"
            end

            # The push word is spent by the push it allows.
            def pushed(found, dir)
                top = PushWord.top(dir)
                return PushWord.record(top) if PushWord.unspent?(found, top)

                "git push needs the user's push word: none was given on " \
                    "a piece of #{found.map(&:address).join(", ")} since " \
                    "the last push"
            end

            # The [ledger, piece] pairs whose commit word was given.
            def given(found)
                found.flat_map do |ledger|
                    ledger.derive.pieces.filter_map do |piece|
                        [ledger, piece] if
                            CommitWord.given?(ledger.snapshot, piece)
                    end
                end
            end

            # Whether the merge of CALL's operands lands a commit in the
            # repository at DIR; false when none, or when they cannot be
            # told.
            def landing?(call, dir)
                return false if call.args.intersect?(ENDS)

                operands(call.args).any? do |branch|
                    !lines(dir, "rev-list", "HEAD..#{branch}").empty?
                end
            end

            def operands(args)
                skip = false
                args.reject do |arg|
                    gone = skip || arg.start_with?("-")
                    skip = !skip && OPTION_VALUE.include?(arg)
                    gone
                end
            end

            def lines(dir, *)
                return [] unless File.directory?(dir)

                out, _, status = Open3.capture3("git", "-C", dir, *)
                status.success? ? out.lines(chomp: true) : []
            end

            def deny(reason)
                { hookSpecificOutput: { hookEventName: "PreToolUse",
                                        permissionDecision: "deny",
                                        permissionDecisionReason:
                                            "Refused: #{reason}." } }
            end
        end
    end
end
