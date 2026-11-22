# frozen_string_literal: true

require_relative "../helper"

require "digest"
require "ledger/derive"

# A ledger built row by row on the fixture journal, a criterion met and
# a goal given, so that a test adds only the rows its rule reads; the
# base of every check test.
class CheckCase < JournalTest
    def setup
        super
        @rows = Ledger::Change.new(db, @ledger, event)
        goal
        criterion(mark: "x", evidence: "seen")
    end

    def event
        db[:events].insert(ledger_id: @ledger[:id], at: 1, actor: "cli",
                           command: "fixture", argv: "[]")
    end

    def snapshot = Ledger::Snapshot.read(db, @ledger[:id])
    def derive = Ledger::Derive.new(snapshot)

    def report(name, final: false)
        Ledger::Checks.run(snapshot, final:).find { it[0] == name }
    end

    def assert_fails(name, detail, final: false)
        assert_equal [name, false, detail], report(name, final:)
    end

    def assert_passes(name, final: false)
        assert_equal [name, true, ""], report(name, final:)
    end

    def goal(**columns)
        @rows.insert(:goals, n: @rows.next_id("G"),
                             stamp: "2026-11-20, verbatim", date: "2026-11-20",
                             revised: false, title: "Ledger in Ruby",
                             short: "one journal", quote: "go full ruby now",
                             **columns)
    end

    def criterion(**columns)
        @rows.insert(:criteria, n: @rows.next_id("D"), mark: " ",
                                text: "a check", **columns)
    end

    # A planned piece with a route, verified by me when verified; returns
    # its row id.
    def piece(**columns)
        n = @rows.next_id("P")
        by = "me" if columns[:status] == "verified"
        @rows.insert(:pieces, n:, status: "planned", model: "sonnet",
                              effort: "low", dash: false,
                              title: "Piece number #{n}", verified_by: by,
                              **columns)
    end

    def after(piece_id, *after_ids)
        after_ids.each_with_index do |id, position|
            @rows.insert(:piece_links, piece_id:, kind: "after", position:,
                                       after_id: id)
        end
    end

    def awaits(piece_id, *words)
        words.each_with_index do |word, position|
            @rows.insert(:piece_awaits, piece_id:, position:, word:)
        end
    end

    # An open question, answerable and well described; returns its id.
    def question(options = ["A = keep it", "B = drop the cache"], **columns)
        id = @rows.insert(:questions, n: @rows.next_id("O"),
                                      title: "Cache policy",
                                      detail: "Which cache policy holds?",
                                      problem: "stale", risk: "3/10 — slow",
                                      risk_rating: 3,
                                      recommend: "A, it is simpler",
                                      **columns)
        choices(id, options)
        id
    end

    def choices(question_id, options)
        options.each_with_index do |option, position|
            choice(question_id, option, position)
        end
    end

    def choice(question_id, option, position)
        label, effect, cost = Ledger::Text::Options.parts(option)
        @rows.insert(:question_choices, question_id:, position:, label:,
                                        effect: (effect unless effect.empty?),
                                        cost: (cost unless cost.empty?))
    end

    def update(table, id, **columns) = @rows.update(table, id, **columns)
end

# The runner: the order of the rules, the --final ones, the shape the
# write path compares, a hint for every rule.
class ChecksRunnerTest < CheckCase
    ALWAYS = %w[goal-titled goal-revision criteria open-choices
                open-described open-picker self-routed links question-loop
                pieces-awaits pictures pictures-fresh pictures-options titles
                details codes pieces-order
                criteria-pieces case-rated verified-by assumptions-refuted
                assumptions-settled].freeze
    FINAL = %w[final-pieces final-deferred final-awaits
               final-criteria final-commits].freeze

    def test_the_rules_run_in_order_and_final_adds_five
        assert_equal ALWAYS, Ledger::Checks.run(snapshot).map(&:first)
        assert_equal ALWAYS + FINAL,
                     Ledger::Checks.run(snapshot, final: true).map(&:first)
    end

    def test_a_sound_ledger_passes_every_rule
        assert_empty Ledger::Checks.failures(snapshot, final: true)
    end

    def test_failures_are_name_and_detail
        piece(status: "out", claimed_by: "s")

        assert_equal [["final-pieces", "still open: P1 [out]"]],
                     Ledger::Checks.failures(snapshot, final: true)
    end

    def test_every_rule_has_a_hint
        (ALWAYS + FINAL).each { refute_empty Ledger::Checks.hint(it) }
        assert_equal (ALWAYS + FINAL).sort, Ledger::Checks::HINTS.keys.sort
    end

    # The table pinned: the rule names and a digest of every name and
    # text, sorted.
    HINT_KEYS = %w[
        assumptions-refuted assumptions-settled case-rated codes criteria
        criteria-pieces details final-awaits final-commits final-criteria
        final-deferred final-pieces goal-revision goal-titled links open-choices
        open-described open-picker pictures pictures-fresh pictures-options
        pieces-awaits pieces-order question-loop self-routed titles
        verified-by
    ].freeze
    HINT_DIGEST =
        "1ba4af0f4f04d523e4b7e9d50646b4c6e57629a98bcddb227ffd9e0517ee40e7"

    def test_the_hints_cover_exactly_the_rules_runner_defines
        hints = Ledger::Checks::HINTS

        assert_equal Ledger::Checks::RULES.map(&:name).sort, hints.keys.sort
    end

    def test_the_merged_hints_are_the_pinned_table
        hints = Ledger::Checks::HINTS
        joined = hints.sort.map { |name, text| "#{name}\0#{text}" }.join("\n")

        assert_equal HINT_KEYS, hints.keys.sort
        assert_equal HINT_DIGEST, Digest::SHA256.hexdigest(joined)
    end

    def test_the_write_path_refuses_a_write_that_breaks_a_rule
        error = assert_raises(Ledger::Worse) do
            write(checks: Ledger::Checks) do |change|
                id = piece_in(change)
                change.insert(:piece_awaits, piece_id: id, position: 0,
                                             word: "commit")
            end
        end

        assert_match(/\AFAIL pieces-awaits -- P1 \[planned\] awaits commit/,
                     error.message)
    end

    def piece_in(change)
        change.insert(:pieces, n: change.next_id("P"), status: "planned",
                               model: "opus", effort: "low", dash: false,
                               title: "Some piece", problem: "p",
                               risk: "2/10 — x", risk_rating: 2)
    end
end
