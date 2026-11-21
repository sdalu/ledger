# frozen_string_literal: true

require_relative "helper"

# `renumber`: one n changes, its id printed first, references following
# by key, the counter never giving NEW again.
class RenumberTest < CommandCase
    ROUTE = ["--route", "haiku, effort: low"].freeze

    def setup
        super
        ok("piece", BETA, "new", "--title", "Parse the input", *ROUTE)
        ok("piece", BETA, "new", "--title", "Write the output", *ROUTE,
           "--after", "P1")
    end

    def test_references_follow_the_renumbered_item
        out = ok("renumber", BETA, "P1", "P5")
        assert_equal ["P5", "renumbered P1 -> P5: its heading and 1 " \
                            "reference(s)"], out.lines(chomp: true)[0..1]
        assert_includes markdown, "- P5 [planned]"
        assert_includes markdown, "— after: P5"
        assert_equal "P6", ok("piece", BETA, "new", "--title",
                              "Check the result", *ROUTE).lines.first.chomp
    end

    def test_the_shapes_of_old_and_new
        assert_refused("renumber", BETA, "P1", "X5", "OLD and NEW are ids")
        assert_refused("renumber", BETA, "P1", "D5",
                       "P1 and D5 are not the same kind")
        assert_refused("renumber", BETA, "P1", "P1", "OLD and NEW are the same")
    end

    def test_old_heads_an_item
        assert_refused("renumber", BETA, "F1", "F4",
                       "F1 heads no item in #{BETA}")
    end

    def test_an_untaken_entry_about_old
        Ledger::Write.run(@journal, BETA, "inbox", []) do |change|
            change.insert(:inbox_entries, n: 1, at: "2026-11-20 10:00:00",
                                          ref: "P1", payload: "{}")
        end
        assert_refused("renumber", BETA, "P1", "P5",
                       "the inbox holds N1 not taken, about P1")
    end

    def test_new_given_before_or_named
        assert_refused("renumber", BETA, "P1", "P2",
                       "P2 heads an item, is named by a reference, or was " \
                       "given before")
        Ledger::Write.run(@journal, BETA, "inbox", []) do |change|
            change.insert(:inbox_entries, n: 1, at: "2026-11-20 10:00:00",
                                          ref: "P7", payload: "{}")
        end
        assert_refused("renumber", BETA, "P1", "P7", "P7 heads an item")
    end

    def test_a_dry_run_writes_nothing
        before = state
        out = ok("renumber", BETA, "P1", "P5", "--dry-run")
        assert_equal "P5", out.lines.first.chomp
        assert_includes out, "dry run: nothing written"
        assert_equal before, state
    end
end
