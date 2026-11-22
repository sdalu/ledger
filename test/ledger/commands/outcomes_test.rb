# frozen_string_literal: true

require_relative "helper"
require "ledger/outcomes"

# The writers' outcomes: a refusal recorded under its rule after the
# write rolled back, a check's flags on and off, the close's
# after-action block on its event; the recorder never raises; undo leaves
# the rows and a purge takes them with the ledger.
class OutcomesTest < CommandCase
    HOUR_MS = 3_600_000

    def outcomes = db[:outcomes].order(:id).all
    def columns(*names) = outcomes.map { it.values_at(*names) }
    def refusals = columns(:kind, :rule, :ledger_id)

    def test_a_writer_refusal_is_recorded_under_its_rule
        ENV["CLAUDE_CODE_SESSION_ID"] = "s9"
        assert_refused("new", "/work/beta/.claude/LEDGER.md", *GOAL,
                       "a live ledger already sits here")

        assert_equal 1, outcomes.size
        row = outcomes.first
        assert_equal ["refusal", "second-ledger", nil, "s9"],
                     row.values_at(:kind, :rule, :ledger_id, :session)
        assert_includes row[:detail], "ask the user"
    ensure
        ENV.delete("CLAUDE_CODE_SESSION_ID")
    end

    def test_a_refusal_names_the_ledger_and_the_item
        assert_refused("word", BETA, "P7", "--word", "start", "no P7")

        assert_equal [["refusal", "refused", @beta, "P7"]],
                     columns(:kind, :rule, :ledger_id, :ref)
    end

    def test_a_usage_refusal_is_recorded_as_usage
        cli("fact", BETA)
        cli("fact", BETA, "--nope")

        assert_equal [["refusal", "usage", @beta]] * 2, refusals
    end

    def test_a_worse_write_records_each_rule_it_fails
        worse = Ledger::Worse.new("FAIL a-rule -- x\nFAIL b-rule")
        rows = Ledger::Commands::RefusalOutcomes.new([BETA], err: $stderr)
                                                .rows(worse)

        assert_equal([%w[a-rule x], ["b-rule", nil]],
                     rows.map { it.values_at(:rule, :detail) })
    end

    def test_a_read_word_refusal_is_not_recorded
        cli("show", "/work/none/LEDGER.md")

        assert_empty outcomes
    end

    # P1 out since five hours: stalled.
    def stalled_piece
        Ledger::Write.run(@journal, BETA, "piece", [],
                          at: Ledger::Write.now - (5 * HOUR_MS)) do |change|
            piece(change, status: "out")
        end
    end

    def test_a_check_records_a_flag_on_then_off
        stalled_piece
        cli("check", BETA)
        cli("check", BETA)
        cli("check", "--peek", BETA)
        assert_equal [%w[flag_on stalled P1]], columns(:kind, :rule, :ref)

        ok("piece", BETA, "P1", "--status", "planned", "--cause", "env")
        cli("check", BETA)
        assert_equal %w[flag_off stalled P1],
                     outcomes.last.values_at(:kind, :rule, :ref)
    end

    def test_the_close_keeps_its_after_action_block
        out = ok("close", BETA, "--abandon")
        summary = db[:events].where(ledger_id: @beta, command: "close")
                             .get(:summary)

        assert_equal Ledger::AfterAction::EMPTY, summary
        assert out.start_with?("#{summary}\n")
    end

    def test_the_recorder_swallows_a_failure_in_one_line
        db.drop_table(:outcomes)
        err = StringIO.new

        refute Ledger::Outcomes.record(kind: "refusal", rule: "r", err:)
        assert_equal 1, err.string.lines.size
        assert_match(/\Aledger: outcome not recorded: .*outcomes/, err.string)
    end

    def test_the_recorder_writes_nothing_without_a_journal
        ENV["LEDGER_JOURNAL"] = File.join(@dir, "none.db")

        refute Ledger::Outcomes.record(kind: "refusal", rule: "r")
        refute File.exist?(ENV.fetch("LEDGER_JOURNAL"))
    ensure
        ENV["LEDGER_JOURNAL"] = @journal.path
    end

    def test_undo_leaves_the_outcomes
        ok("fact", BETA, "a — b")
        cli("fact", BETA)
        ok("undo", BETA)

        assert_equal [["refusal", "usage", @beta]], refusals
    end

    def test_a_purge_takes_the_ledger_s_outcomes
        cli("fact", BETA)
        Ledger::Outcomes.record(kind: "refusal", rule: "other")
        ok("close", BETA, "--abandon")
        ok("purge", "L#{@beta}", "--confirmed")

        assert_equal [["refusal", "other", nil]], refusals
    end

    def test_stats_counts_the_outcomes_by_kind_and_rule
        cli("fact", BETA)
        cli("fact", BETA)
        Ledger::Outcomes.record(kind: "refusal", rule: "usage")
        out = ok("stats")

        assert_match(/^outcomes\n.*\nrefusal +usage +3 +L#{@beta} 2$/, out)
        assert_match(/^refusal +usage +2 +L#{@beta} 2$/, ok("stats", BETA))
        json = JSON.parse(ok("stats", "--json"))["outcomes"]
        assert_equal [{ "kind" => "refusal", "rule" => "usage", "count" => 3,
                        "ledgers" => { "L#{@beta}" => 2 } }], json
    end
end
