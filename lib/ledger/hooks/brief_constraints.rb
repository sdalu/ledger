# frozen_string_literal: true

require "ledger/hooks/ledgers"

module Ledger
    module Hooks
        # PreToolUse on Agent: a brief that names a path one of the
        # session's constraints names must carry that constraint's quote
        # verbatim (whitespace and case folded), or the dispatch is
        # denied. A constraint naming no path is never enforced here: a
        # brief cannot be shown to touch it without judgment.
        module BriefConstraints
            # A path in a brief (\w as Unicode).
            PATH = %r{(?<![[:word:]/])
                      ((?:~/|\.{0,2}/)?[[:word:].-]+(?:/[[:word:].-]*)+
                      |[[:word:]-]+\.(?:py|c|h|rb|md|json|ya?ml|toml|js|ts|
                                       go|rs|sh|bib|tex|csv|txt))
                      (?![[:word:]])}x
            TOOLS = %w[Agent Task].freeze

            module_function

            def call(payload)
                return Answer.pass unless TOOLS.include?(payload["tool_name"])
                input = payload["tool_input"]
                brief = input.is_a?(Hash) ? input["prompt"].to_s : ""
                missing = Ledgers.read(payload, derive: false)
                                 .flat_map { missing(it.snapshot, brief) }
                missing.empty? ? Answer.pass : Answer.json(deny(missing))
            end

            # -> [[C<n>, quote, the first path the brief touches]].
            def missing(snapshot, brief)
                folded = fold(brief)
                snapshot.constraints.filter_map do |row|
                    touched = paths(row[:quote]).find { brief.include?(it) }
                    next unless touched && !folded.include?(fold(row[:quote]))
                    ["C#{row[:n]}", row[:quote], touched]
                end
            end

            def paths(text)
                text.scan(PATH).flatten.map { it.sub(/[.,;:]+\z/, "") }
            end

            def fold(text)
                text.split(/[[:space:]]+/).reject(&:empty?)
                    .join(" ").downcase(:fold)
            end

            def deny(missing)
                { hookSpecificOutput: { hookEventName: "PreToolUse",
                                        permissionDecision: "deny",
                                        permissionDecisionReason:
                                            reason(missing) } }
            end

            def reason(missing)
                lines = missing.map do |id, quote, path|
                    "#{id} (\"#{quote}\", it names #{path})"
                end
                "Dispatch refused: the brief touches a path a ledger " \
                    "constraint names but does not carry the constraint " \
                    "verbatim: #{lines.join("; ")}. Copy each into the brief " \
                    "word for word (orchestration, Dispatch): the delegate " \
                    "never saw the turn it was said in."
            end
        end
    end
end
