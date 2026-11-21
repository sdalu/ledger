# frozen_string_literal: true

require_relative "helper"

# brief-constraints: a brief naming a path a constraint names carries
# the constraint's quote, or the dispatch is denied.
class BriefConstraintsTest < HookTest
    QUOTE = "never touch vendor/ by hand"

    def setup
        super
        write("import") do |change|
            constraint(change, QUOTE)
            constraint(change, "no customer email anywhere")
        end
    end

    def dispatch(prompt, cwd: PLACE)
        answer = hook("brief-constraints", tool_name: "Agent", cwd:,
                                           tool_input: { prompt: })
        answer.out && json(answer)["hookSpecificOutput"]
    end

    def test_a_brief_touching_the_path_without_the_quote_is_denied
        out = dispatch("Update vendor/lib.rb and the docs")

        assert_equal "deny", out["permissionDecision"]
        assert_match "C1 (\"#{QUOTE}\", it names vendor/)",
                     out["permissionDecisionReason"]
    end

    def test_the_quote_carried_folded_passes
        assert_nil dispatch("Update vendor/lib.rb. Rule: Never touch\n" \
                            "VENDOR/ by  hand")
    end

    def test_a_brief_naming_no_path_and_another_place_pass
        assert_nil dispatch("Write the customer report")
        assert_nil dispatch("Update vendor/lib.rb", cwd: "/work/beta")
    end
end
