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

    def test_and_or_is_no_path_and_a_file_is_its_own_token
        write("files") do |change|
            constraint(change, "keep lib/a.rb stable", "the user, turn 2")
        end

        assert_nil dispatch("Do vendor and/or lib work, not vendor/x")
        assert_nil dispatch("Edit lib/a.rbx and notes")
        assert_nil dispatch("Edit ./lib/a.rb2 only")
        assert_equal "deny", dispatch("Edit lib/a.rb now")["permissionDecision"]
    end

    def test_a_directory_covers_the_paths_under_it
        out = dispatch("Edit vendor/deep/x.rb")

        assert_equal "deny", out["permissionDecision"]
        assert_nil dispatch("Edit lib/x.rb with and/or")
    end

    def test_a_brief_naming_no_path_and_another_place_pass
        assert_nil dispatch("Write the customer report")
        assert_nil dispatch("Update vendor/lib.rb", cwd: "/work/beta")
    end
end
