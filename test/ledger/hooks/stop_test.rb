# frozen_string_literal: true

require_relative "helper"

# The two Stop hooks: finish sends back a finished ledger that fails
# --final; inbox sends back entries no take recorded. Both let the
# retry through.
class StopTest < HookTest
    # The two entries as the hook shows them, verbatim.
    SHOWN = <<~TEXT.chomp
        #{JournalTest::ADDRESS}:
        N1 (2026-11-20 10:00:00, answer to O2):
            chose: B
            on A:
              too slow
            line one
            line two
        N2 (2026-11-20 10:00:00, word on P4: commit):
            word: commit
    TEXT

    def stop(name, **payload) = hook(name, **payload)

    def test_a_finished_ledger_failing_final_is_sent_back_once
        write("import") do |change|
            goal(change)
            criterion(change)
            piece(change, status: "verified", evidence: "ran it")
        end
        answer = stop("finish")

        assert_equal 2, answer.status
        assert_match "bin/ledger check --final ADDRESS", answer.err
        assert_match "#{ADDRESS}: FAIL final-criteria", answer.err
        assert_equal 0, stop("finish", stop_hook_active: true).status
    end

    def test_a_ledger_still_in_flight_or_waiting_is_let_through
        write("import") do |change|
            goal(change)
            criterion(change)
            piece(change)
        end

        assert_equal Ledger::Hooks::Answer.pass, stop("finish")
        write("import") { question(it) }

        assert_equal Ledger::Hooks::Answer.pass, stop("finish")
    end

    def test_pending_entries_refuse_the_stop_verbatim
        write("import") do |change|
            entry(change, ref: "O2", choice: "B", text: "line one\nline two",
                          notes: { "A" => "too slow" })
            entry(change, ref: "P4", word: "commit", text: "")
        end
        answer = stop("inbox")

        assert_equal 2, answer.status
        assert_match "`bin/ledger take ADDRESS N<n>...`", answer.err
        assert_includes answer.err, SHOWN
    end

    def test_taken_entries_and_the_retry_pass
        write("import") { entry(it, text: "a note") }

        assert_equal 0, stop("inbox", stop_hook_active: true).status
        db[:inbox_entries].update(taken_id: db[:events].max(:id))

        assert_equal Ledger::Hooks::Answer.pass, stop("inbox")
    end
end
