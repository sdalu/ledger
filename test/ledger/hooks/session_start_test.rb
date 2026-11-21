# frozen_string_literal: true

require_relative "helper"
require "ledger/hooks/resume_view"

# session-start: waiting entries on every source, the resume view on
# startup, resume and compact, within its budget.
class SessionStartTest < HookTest
    def context(source)
        answer = hook("session-start", source:)
        answer.out &&
            json(answer).dig("hookSpecificOutput", "additionalContext")
    end

    def fill(pieces: 3, questions: 2)
        write("import") do |change|
            goal(change, quote: "the first words")
            goal(change, quote: "the revised words", revised: true)
            constraint(change, "keep vendor/ untouched")
            questions.times { question(change) }
            pieces.times { piece(change) }
        end
    end

    def found = Ledger::Hooks::Ledgers.read({ "cwd" => PLACE })

    def test_the_view_holds_goals_constraints_open_and_in_flight
        fill
        text = context("startup")

        assert text.start_with?("Ledger #{ADDRESS} — bin/ledger show " \
                                "#{ADDRESS} for the whole\n" \
                                "Status (#{ADDRESS}) — ")
        ["> the first words", "> the revised words",
         "- C1: \"keep vendor/ untouched\"", "Open:\n- O1: Title 1",
         "In flight:\n- P1 [planned]"].each { assert_includes text, it }
        assert_match(/^- P3 \[planned\] .* \(ready\)$/, text)
    end

    def test_a_piece_ready_past_the_limit_is_listed_with_its_age
        at = 1_700_000_000_000
        write("import", [], at:) { piece(it) }
        hour = 3_600_000

        under = render_at(at + hour)
        past = render_at(at + (3 * hour))

        refute_includes under, "Ready, unsent:"
        assert_match(/^Ready, unsent:\n- P1 \[planned\] .* \(3 h\)$/, past)
        assert_match(/^In flight:\n- P1 \[planned\] .* \(ready\)$/, past)
    end

    def render_at(now)
        found = Ledger::Hooks::Ledgers.read({ "cwd" => PLACE }, now:)
        Ledger::Hooks::ResumeView.render(found)
    end

    def test_in_flight_lists_a_deferred_piece_with_its_condition
        write("import") do |change|
            piece(change, status: "deferred", until: "three closures")
        end

        text = context("startup")

        assert_includes text, "In flight:\n- P1 [deferred] "
        assert_match(/^- P1 .* — until: three closures$/, text)
    end

    def assumption(change, state)
        change.insert(:assumptions, n: change.next_id("A"),
                                    text: "it is #{state}", check: "try it",
                                    state:)
    end

    def test_the_open_assumptions_are_listed_with_their_check
        write("import") do |change|
            %w[open confirmed].each { assumption(change, it) }
        end
        text = context("startup")

        assert_includes text, "Assuming:\n- A1 [open] it is open — check: " \
                              "try it"
        refute_includes text, "A2 [confirmed]"
        assert_includes text, "assuming: A1"
    end

    def test_clear_shows_nothing_but_entries
        fill

        assert_nil context("clear")
        write("import") { entry(it, text: "while you were away") }

        assert_match(/\AEntries are waiting.*before anything else/m,
                     context("clear"))
        assert_includes context("resume"), "Ledger #{ADDRESS}"
    end

    def test_over_budget_pieces_then_questions_drop_from_the_end
        fill(pieces: 30, questions: 10)
        full = Ledger::Hooks::ResumeView.render(found)
        text = Ledger::Hooks::ResumeView.render(found,
                                                budget: full.size - 200)

        assert_operator text.size, :<=, full.size - 200
        assert_match(%r{^… \d+ more: bin/ledger show #{ADDRESS}\z}, text)
        assert_includes text, "- O10: Title 10"
    end

    def test_goals_and_constraints_over_budget_keep_the_latest_goal
        fill
        text = Ledger::Hooks::ResumeView.render(found, budget: 300)

        assert_includes text, "> the revised words"
        refute_includes text, "> the first words"
        assert_includes text, "Constraints: C1, in full: bin/ledger show"
        assert_includes text, "… 2 more: bin/ledger show"
    end

    def test_the_budget_is_shared_between_ledgers
        fill
        @journal.create_ledger("#{PLACE}/LEDGER-two.md", project: "alpha")
        parts = Ledger::Hooks::ResumeView.render(found, budget: 1000)
                                         .split(/\n\n(?=Ledger )/)

        assert_equal 2, parts.size
        parts.each { assert_operator it.size, :<=, 499 }
    end
end
