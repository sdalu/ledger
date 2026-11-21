# frozen_string_literal: true

require_relative "helper"

# `new`: a live ledger with its Goal block, the placeholder criterion and
# the noticed lines carried from a closed one.
class NewTest < CommandCase
    GAMMA = "/work/gamma/.claude/LEDGER-web.md"

    def test_a_ledger_is_made_and_its_address_printed
        assert_equal "#{GAMMA}\n", ok("new", GAMMA, *GOAL)
        row = db[:ledgers].where(name: "web").first
        assert_equal "gamma", row[:project]
        assert_equal 1, db[:events].where(ledger_id: row[:id]).count
    end

    def test_the_first_goal_block_and_the_placeholder_criterion
        ok("new", GAMMA, *GOAL)
        id = db[:ledgers].where(name: "web").get(:id)
        snap = Ledger::Snapshot.read(db, id)
        assert_equal "2026-11-20, verbatim", snap.goals.first[:stamp]
        assert_equal "<a check something other than opinion can pass>",
                     snap.criteria.first[:text]
    end

    def test_a_live_address_is_refused
        assert_refused("new", BETA, *GOAL, "exists; refusing to overwrite")
    end

    def test_a_title_that_is_not_a_title_is_refused
        assert_refused("new", GAMMA, "--goal", "go now please", "--title",
                       "Why: because", "--short", "s",
                       "new: the title holds `: `")
    end

    def test_an_empty_short_is_refused
        assert_refused("new", GAMMA, "--goal", "go now please", "--title",
                       "Some title", "--short", " ", "--short is empty")
    end

    def test_an_empty_goal_or_a_wrong_date_is_refused
        assert_refused("new", GAMMA, "--goal", " ", "--title", "Some title",
                       "--short", "s", "the quote is empty")
        assert_refused("new", GAMMA, *GOAL, "--date", "20-11-2026",
                       "--date is YYYY-MM-DD")
    end

    def test_a_missing_option_is_a_usage_error
        assert_refused("new", GAMMA, "--title", "Some title", "--short", "s",
                       "--goal is required")
    end

    def test_carry_names_no_closed_ledger
        assert_refused("new", GAMMA, *GOAL, "--carry", "L999",
                       "--carry L999: no closed ledger")
        assert_refused("new", GAMMA, *GOAL, "--carry", BETA,
                       "no closed ledger")
    end

    def test_carry_takes_the_noticed_lines_of_a_closed_ledger
        ok("noticed", BETA, "side thing")
        ok("criterion", BETA, "D1", "--met", "seen")
        ok("close", BETA)
        ok("new", GAMMA, *GOAL, "--carry", BETA)
        gamma = db[:ledgers].where(name: "web").get(:id)
        assert_equal ["- side thing"],
                     db[:noticed].where(ledger_id: gamma).select_map(:line)
        ok("new", "/work/delta/LEDGER.md", *GOAL, "--carry",
           "L#{@beta}")
    end
end
