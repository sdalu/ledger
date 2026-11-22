# frozen_string_literal: true

require "json"

require_relative "helper"

# `brief PATH P<n>`: the JSON a brief for a piece is built from, each
# block on a fixture ledger, nothing written; a piece missing exits 2.
class BriefTest < CommandCase
    def setup
        super
        goals
        ok("constraint", BETA, "keep lib/ledger/x.rb small", "--where",
           "turn 3")
        facts
        built
        decisions
    end

    # The question O1 and the piece P1 that builds it.
    def built
        ok("ask", BETA, "Which parser?", "--title", "Parser choice",
           "--problem", "two fit", "--risk", "2/10 — a redo", "--see", "F5",
           "--no-picture", "words alone")
        ok("piece", BETA, "new", "--title", "Ship the parser", "--route",
           "opus, effort: high", "--what", "rework lib/ledger/x.rb",
           "--done-when", "its tests pass", "--builds", "O1")
    end

    def goals
        ok("goal", BETA, "G1", "--done", "built")
        ok("goal", BETA, "--quote", "and then make it fast too please",
           "--title", "Fast", "--short", "make it fast")
    end

    def facts
        ["the parser lives here — lib/ledger/x.rb:10",
         "elsewhere — docs/other.md", "the go-ahead rests here — turn 4",
         "the belief rests here — turn 5", "the question cites it — turn 6"]
            .each { ok("fact", BETA, it) }
    end

    def decisions
        ok("answer", BETA, "O1", "--decision", "the small one")
        ok("decide", BETA, "go on", "--by", "user", "--led-to", "P1",
           "--rests-on", "F3")
        ok("decide", BETA, "my own idea", "--by", "me", "--led-to", "P1")
        ok("assume", BETA, "it holds — run it", "--see", "F4", "--for", "P1")
    end

    def brief = JSON.parse(ok("brief", BETA, "P1"), symbolize_names: true)

    def test_the_piece_and_its_route
        assert_equal({ id: "P1", title: "Ship the parser",
                       what: "rework lib/ledger/x.rb",
                       done_when: "its tests pass",
                       route: "opus, effort: high" }, brief[:piece])
    end

    def test_the_goals_not_done
        assert_equal [{ id: "G2", title: "Fast", short: "make it fast",
                        quote: "and then make it fast too please" }],
                     brief[:goals]
    end

    def test_the_constraints_with_where
        assert_equal [{ id: "C1", quote: "keep lib/ledger/x.rb small",
                        where: "turn 3" }], brief[:constraints]
    end

    def test_the_facts_pointed_or_linked
        assert_equal(%w[F1 F3 F4 F5], brief[:facts].map { it[:id] })
        assert_equal({ id: "F1", text: "the parser lives here",
                       pointer: "lib/ledger/x.rb:10" }, brief[:facts].first)
    end

    def test_the_question_built_and_its_answer
        assert_equal({ question: "O1", decision: "X1",
                       text: "O1: the small one" }, brief[:builds])
    end

    def test_the_decisions_by_user_behind_it
        assert_equal [{ id: "X2", date: Time.now.strftime("%F"),
                        text: "go on" }], brief[:answers]
    end

    def test_nothing_is_written
        before = state
        brief
        assert_equal before, state
    end

    def test_a_missing_piece_is_refused
        assert_refused("brief", BETA, "P9", "no P9 under Pieces in #{BETA}")
        assert_refused("brief", BETA, "O1", "the target is P<n>")
    end
end
