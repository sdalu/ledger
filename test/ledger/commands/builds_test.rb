# frozen_string_literal: true

require "json"

require_relative "piece_test"

# What the tests of `piece --builds` and `--status obsolete` share:
# BETA with O1 open, P1 and P2 awaiting their start, P2 building O1.
class BuildsCase < PieceCase
    QUESTION = ["Which way?", "--title", "Which way", "--problem", "two ways",
                "--risk", "2/10 — a detour", "--choices",
                "A = left | B = right", "--recommend", "A, shorter",
                "--no-picture", "a choice of words"].freeze
    WAITS = ["--awaits", "start", *PieceCase::CASE, "--no-picture",
             "a probe"].freeze

    def setup
        super
        ok("ask", BETA, *QUESTION)
        add(*WAITS)
        add(*WAITS, "--builds", "O1", "--plan", "go left")
    end

    def json(id) = document["pieces"].find { it["id"] == id }

    def document = JSON.parse(ok("show", BETA, "--json"))

    def question_id = db[:questions].where(ledger_id: @beta, n: 1).get(:id)
end

# `piece --builds O<n>`: the question a piece builds, one piece a
# question, no start before the answer, in `show --json` with the
# decision that answered it.
class BuildsTest < BuildsCase
    def test_builds_is_stored_and_shown_in_json
        assert_equal question_id, row(2)[:builds_id]
        assert_equal({ "question" => "O1", "decision" => nil, "text" => nil },
                     json("P2")["builds"])
        assert_nil json("P1")["builds"]
    end

    def test_none_clears_it
        ok("piece", BETA, "P2", "--builds", "none")

        assert_nil row(2)[:builds_id]
    end

    def test_one_piece_builds_a_question
        refused("P1", "--builds", "O1",
                "O1 is built by P2: one piece builds a question")
        ok("piece", BETA, "P2", "--builds", "O1")
    end

    def test_an_answered_unknown_or_misshapen_question_is_refused
        refused("P1", "--builds", "O9", "no O9 under Open")
        refused("P1", "--builds", "X1", "--builds takes O<n> or none, not X1")
        ok("answer", BETA, "O1", "--decision", "A")
        ok("ask", BETA, *QUESTION)
        ok("answer", BETA, "O2", "--decision", "B")
        refused("P1", "--builds", "O2",
                "O2 is answered: --builds names an open question")
    end

    def test_start_waits_for_the_answer
        assert_refused("word", BETA, "P2", "--word", "start",
                       "P2 builds O1: answer O1 first")
        ok("answer", BETA, "O1", "--decision", "A, left")
        ok("word", BETA, "P2", "--word", "start")

        assert_equal({ "question" => "O1", "decision" => "X1",
                       "text" => "O1: A, left" }, json("P2")["builds"])
    end
end

# `piece --status obsolete --obsoleted-by P<n>`: the piece another
# replaces, out of every count and of `check --final`, in `show --json`.
class ObsoleteTest < BuildsCase
    def test_obsolete_names_its_replacement_on_the_line
        out = ok("piece", BETA, "P1", "--status", "obsolete",
                 "--obsoleted-by", "P2")

        assert_includes out, "- P1 [obsolete] sonnet, effort: medium — " \
                             "Build the parser — obsoleted by P2"
        assert_equal "P2", json("P1")["obsoleted_by"]
        assert_empty json("P1")["awaits"]
        assert_nil json("P2")["obsoleted_by"]
    end

    def test_another_status_clears_the_replacement
        ok("piece", BETA, "P1", "--status", "obsolete", "--obsoleted-by", "P2")
        ok("piece", BETA, "P1", "--status", "planned")

        assert_nil row[:obsoleted_by_id]
    end

    def test_obsolete_and_obsoleted_by_go_together
        refused("P1", "--status", "obsolete",
                "--status obsolete needs --obsoleted-by P<n>")
        refused("P1", "--obsoleted-by", "P2",
                "--obsoleted-by goes with --status obsolete")
        refused("P1", "--status", "planned", "--obsoleted-by", "P2",
                "--obsoleted-by goes with --status obsolete")
    end

    def test_a_dropped_replacement_is_refused
        add
        ok("piece", BETA, "P3", "--status", "dropped")
        refused("P1", "--status", "obsolete", "--obsoleted-by", "P3",
                "P3 is dropped: it replaces nothing")
    end

    def test_an_obsolete_unknown_or_same_replacement_is_refused
        ok("piece", BETA, "P2", "--status", "obsolete", "--obsoleted-by", "P1")
        refused("P1", "--status", "obsolete", "--obsoleted-by", "P2",
                "P2 is obsolete: it replaces nothing")
        refused("P1", "--status", "obsolete", "--obsoleted-by", "P1",
                "P1 cannot replace itself")
        refused("P1", "--status", "obsolete", "--obsoleted-by", "P9",
                "no P9 under Pieces")
    end

    # As for a dropped one: a piece still after it is moved first.
    def test_a_piece_waited_for_is_not_made_obsolete
        add("--after", "P1")
        refused("P1", "--status", "obsolete", "--obsoleted-by", "P2",
                "pieces-order -- P3 waits for obsolete P1")
    end

    def test_a_piece_out_is_not_made_obsolete
        ok("piece", BETA, "P1", "--status", "out", "--session", "s1",
           "--awaits", "")
        refused("P1", "--status", "obsolete", "--obsoleted-by", "P2",
                "P1 is out: a piece out is not made obsolete")
    end

    def test_obsolete_is_out_of_the_counts_and_of_the_final_check
        ok("piece", BETA, "P1", "--status", "obsolete", "--obsoleted-by", "P2")
        _, out, = cli("check", BETA, "--final")

        refute_match(/final-pieces.*P1/, out)
        refute_match(/final-awaits.*P1/, out)
        assert_includes out, "pieces 0/1 verified"
    end

    def test_stats_count_obsolete_neither_a_failure_nor_a_return
        ok("piece", BETA, "P1", "--status", "back", "--session", "s1",
           "--awaits", "")
        ok("piece", BETA, "P1", "--status", "obsolete", "--obsoleted-by", "P2")
        group, = Ledger::Stats.read(db, [@beta])

        assert_equal [0, 0, {}],
                     [group.blocked, group.verified, group.returns]
    end

    def test_a_purge_takes_a_piece_building_a_question
        ok("close", BETA, "--abandon")
        ok("purge", "L#{@beta}", "--confirmed")

        assert_equal 0, db[:pieces].where(ledger_id: @beta).count
        assert_equal 0, db[:questions].where(ledger_id: @beta).count
    end
end
