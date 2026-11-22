# frozen_string_literal: true

require "open3"

require "ledger/commit_word"
require "ledger/hooks/git_commands"
require "ledger/hooks/ledgers"

module Ledger
    module Hooks
        # PreToolUse on Bash, in the main session only (a payload with an
        # agent_id is a delegate's): a git commit or git merge in a
        # repository whose project has a live ledger is refused unless
        # the user's commit word is on file for it.
        #
        # - commit: some piece was given its commit word and holds no
        #   commit yet (that word is unspent).
        # - merge: every commit the merge would land, HEAD..BRANCH, is
        #   held by a piece given its commit word; the refusal names
        #   the ones that are not.
        #
        # A git push is not gated. No live ledger, a delegate, or any
        # other command passes silently.
        module WordGate
            GIT = /\bgit\b/
            ABBREV = 7
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
                return unless %w[commit merge].include?(call.action)

                dir = File.expand_path(call.dir.to_s, cwd(payload))
                found = Ledgers.read(payload.merge("cwd" => dir))
                return if found.empty?

                return unspent(found) if call.action == "commit"

                uncovered(found, call, dir)
            end

            def cwd(payload)
                payload["cwd"].to_s.empty? ? Dir.pwd : payload["cwd"].to_s
            end

            def unspent(found)
                open = given(found).any? do |ledger, piece|
                    ledger.derive.commits(piece).empty?
                end
                return if open

                "git commit needs the user's commit word: no piece of " \
                    "#{found.map(&:address).join(", ")} was given one " \
                    "that holds no commit yet"
            end

            def uncovered(found, call, dir)
                landing = landing(call, dir)
                held = given(found).flat_map do |ledger, piece|
                    ledger.derive.commits(piece)
                end
                missing = landing.reject { |sha| held.any? { same?(it, sha) } }
                return if missing.empty?

                "git merge needs the user's commit word: " \
                    "#{missing.join(", ")} belong to no piece given one"
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

            def same?(left, right)
                left.start_with?(right) || right.start_with?(left)
            end

            # The abbreviated ids the merge of CALL's operands would land
            # in the repository at DIR; [] when they cannot be told.
            def landing(call, dir)
                return [] if call.args.intersect?(ENDS)

                operands(call.args).flat_map do |branch|
                    lines(dir, "rev-list", "--reverse", "--abbrev-commit",
                          "--abbrev=#{ABBREV}", "HEAD..#{branch}")
                end.uniq
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
