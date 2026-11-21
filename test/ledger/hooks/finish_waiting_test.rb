# frozen_string_literal: true

require_relative "helper"

# The finish Stop hook on criteria that wait with the deferred pieces:
# unmarked, each served by deferred pieces among its unfinished ones or
# by no piece, they let the stop through while --final still fails;
# beside any other failing rule the stop goes back.
class FinishWaitingTest < HookTest
    def test_criteria_waiting_on_deferred_pieces_are_let_through
        snap = write("import") { waiting(it) }.after

        assert_equal Ledger::Hooks::Answer.pass, hook("finish")
        assert_equal %w[final-deferred final-criteria],
                     Ledger::Checks.failures(snap, final: true).map(&:first)
    end

    def test_criteria_waiting_beside_another_failing_rule_are_sent_back
        write("import") do |change|
            waiting(change)
            piece(change, status: "verified", evidence: "ran it",
                          verified_by: "sonnet, effort: low")
        end
        answer = hook("finish")

        assert_equal 2, answer.status
        assert_match "#{ADDRESS}: FAIL verified-by", answer.err
        assert_match "#{ADDRESS}: FAIL final-criteria -- D1 unmarked; " \
                     "D2 unmarked", answer.err
    end

    private

    # Work verified and kept, D1 unmarked served by deferred P1, D2
    # unmarked served by no piece.
    def waiting(change)
        goal(change, title: "Ledger in Ruby", short: "one journal")
        deferred = piece(change, status: "deferred", until: "three closures",
                                 title: "Judge the practices")
        change.insert(:piece_links, piece_id: deferred, kind: "for",
                                    position: 0,
                                    criterion_id: criterion(change))
        criterion(change)
        piece(change, status: "verified", evidence: "ran it")
        piece(change, status: "kept", model: nil, effort: nil,
                      kept_reason: "mine")
    end
end
