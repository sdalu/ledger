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

    # A second live ledger in a place is a fork the user confirms.
    def test_a_second_ledger_in_a_place_needs_the_users_words
        fork = "/work/beta/.claude/LEDGER-web.md"
        assert_refused("new", fork, *GOAL,
                       "a live ledger already sits here: /work/beta/LEDGER.md")
        assert_refused("new", fork, *GOAL,
                       "append it there (ledger goal /work/beta/LEDGER.md")
        ok("new", fork, *GOAL, "--confirmed", "yes, a second one for the web")

        id = db[:ledgers].where(name: "web").get(:id)
        assert_equal ["\"yes, a second one for the web\" — a second live " \
                      "ledger here, beside /work/beta/LEDGER.md", "user"],
                     db[:decisions].where(ledger_id: id).get(%i[body by])
    end

    def test_confirmed_with_nothing_beside_is_refused
        assert_refused("new", GAMMA, *GOAL, "--confirmed", "yes",
                       "--confirmed: no live ledger sits here")
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
