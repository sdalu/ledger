# frozen_string_literal: true

require_relative "helper"

# The outcomes around the gates: a close the finish gate refuses is a
# refusal `final` per failing check, a purge preview is none, and a
# question's stale picture is a flag on its O<n>.
class OutcomesGatesTest < CommandCase
    HOUR_MS = 3_600_000
    QUESTION = ["Which?", "--title", "Which one", "--problem", "p", "--risk",
                "2/10 — r", "--choices", "A = one | B = two", "--recommend",
                "A, simple", "--no-picture", "w"].freeze

    def columns(*names)
        db[:outcomes].order(:id).map { it.values_at(*names) }
    end

    def test_a_close_refused_by_final_records_each_failing_check
        code, out, = cli("close", BETA)

        assert_equal 1, code
        failing = out.lines(chomp: true).grep(/\AFAIL /)
        refute_empty failing
        assert_equal(failing.map { ["refusal", "final", @beta, it] },
                     columns(:kind, :rule, :ledger_id, :detail))
    end

    def test_a_purge_preview_records_nothing
        ok("close", BETA, "--abandon")
        cli("purge", "L#{@beta}")

        assert_empty columns(:kind)
    end

    # O1 pictured an hour ago, then its detail reworded.
    def stale_question
        ok("ask", BETA, *QUESTION)
        picture("a.png")
        db[:events].where(ledger_id: @beta)
                   .update(at: Sequel[:at] - HOUR_MS)
        ok("edit", BETA, "O1", "--text", "Which, now?")
    end

    def picture(name, *flags)
        file = File.join(@dir, name)
        File.binwrite(file, "\x89PNG\r\n#{name}".b)
        ok("mockup", BETA, file, "--question", "O1", *flags)
    end

    def test_a_question_s_stale_picture_is_a_flag_on_then_off
        stale_question
        cli("check", BETA)
        assert_equal [%w[flag_on pictures-fresh O1]],
                     columns(:kind, :rule, :ref)

        picture("b.png", "--replace")
        cli("check", BETA)
        assert_equal %w[flag_off pictures-fresh O1],
                     columns(:kind, :rule, :ref).last
    end
end
