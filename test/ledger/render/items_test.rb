# frozen_string_literal: true

require_relative "helper"

# The one-line items: Done when, Constraints, Facts and Decisions.
class ItemsTest < RenderTest
    def test_a_criterion_not_yet_checked_ends_with_the_bare_evidence_label
        snap = snapshot { criterion(it, text: "it passes", evidence: "") }

        assert_equal "- [ ] D1: it passes — evidence:", line(snap, "D1")
    end

    def test_a_met_criterion_carries_its_evidence
        snap = snapshot do |change|
            criterion(change, mark: "x", text: "it passes", evidence: "green")
        end

        assert_equal "- [x] D1: it passes — evidence: green", line(snap, "D1")
    end

    def test_an_unmet_criterion_carries_its_reason
        snap = snapshot do |change|
            criterion(change, mark: "-", text: "it passes",
                              why: "out of scope")
        end

        assert_equal "- [-] D1: it passes — why: out of scope",
                     line(snap, "D1")
    end

    def test_a_criterion_with_neither_field_has_no_suffix
        snap = snapshot { criterion(it, text: "it passes") }

        assert_equal "- [ ] D1: it passes", line(snap, "D1")
    end

    def test_done_when_lists_the_criteria_in_order
        out = text do |change|
            goal(change)
            criterion(change, text: "one", evidence: "")
            criterion(change, mark: "x", text: "two", evidence: "e")
        end

        assert_includes out, "Done when:\n- [ ] D1: one — evidence:\n" \
                             "- [x] D2: two — evidence: e\n\nConstraints"
    end

    def test_a_constraint_is_its_text_after_its_id
        snap = snapshot do |change|
            change.insert(:constraints, n: change.next_id("C"),
                                        text: "\"no legacy\" — said today",
                                        quote: "no legacy")
        end

        assert_equal "- C1: \"no legacy\" — said today", line(snap, "C1")
    end

    def test_a_fact_is_its_text_a_dash_and_its_pointer
        snap = snapshot do |change|
            change.insert(:facts, n: change.next_id("F"),
                                  text: "ruby is 3.4", pointer: "ruby -v")
        end

        assert_equal "- F1: ruby is 3.4 — ruby -v", line(snap, "F1")
    end

    def test_a_decision_by_user_prints_neither_its_id_nor_a_note
        snap = snapshot { decision(it, body: "O3: \"A\"", by: "user") }

        assert_equal "- 2026-11-20 — O3: \"A\" — by user", line(snap, "X1")
    end

    def test_a_decision_by_me_with_a_note
        snap = snapshot { decision(it, by: "me", note: "not vetoed") }

        assert_equal "- 2026-11-20 — a call — by me (not vetoed)",
                     line(snap, "X1")
    end

    def test_decisions_and_facts_and_constraints_sections
        out = text do |change|
            goal(change)
            decision(change)
        end

        assert_includes out, "Decisions:\n- 2026-11-20 — a call — by me\n\n" \
                             "Pieces:"
    end

    def test_an_unknown_id_is_refused
        snap = snapshot { goal(it) }

        assert_raises(Ledger::Unknown) { line(snap, "F9") }
        assert_raises(Ledger::Unknown) { line(snap, "nonsense") }
    end

    private

    def decision(change, **columns)
        change.insert(:decisions, n: change.next_id("X"), date: "2026-11-20",
                                  body: "a call", by: "me", **columns)
    end
end
