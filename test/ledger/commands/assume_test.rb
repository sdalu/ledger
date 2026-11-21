# frozen_string_literal: true

require "json"

require_relative "helper"

# The ledger every assume test starts from: P1, a question O1, a fact F1.
class AssumeCase < CommandCase
    ROUTE = ["--route", "sonnet, effort: low"].freeze

    def setup
        super
        ok("piece", BETA, "new", *ROUTE, "--title", "port the lexer")
        ok("ask", BETA, "which one?", "--title", "Lexer generator",
           "--problem", "two tools", "--risk", "3/10 — rework",
           "--choices", "A = re2c | B = by hand", "--recommend", "A, fast",
           "--no-picture", "a choice of words")
        ok("fact", BETA, "re2c is packaged — pkg search re2c")
    end
end

# `assume PATH 'TEXT — CHECK'`: an assumption opened as A<n> with how it
# will be checked, what it rests on and what rests on it.
class AssumeTest < AssumeCase
    def test_an_assumption_is_split_at_its_first_dash_and_printed
        out = ok("assume", BETA, "the spec is LL(1) — parse its samples",
                 "--see", "F1", "--for", "P1,O1")
        assert_equal ["A1", "- A1 [open] the spec is LL(1) — check: parse " \
                            "its samples — see: F1 — for: P1, O1"],
                     out.lines(chomp: true)[0..1]
        assert_match(/assuming: A1/, out.lines.last)
        assert_equal [["the spec is LL(1)", "parse its samples", "open"]],
                     db[:assumptions].select_map(%i[text check state])
    end

    def test_without_see_or_for_it_is_its_text_and_check
        out = ok("assume", BETA, "a — b")
        assert_includes out, "- A1 [open] a — check: b\n"
        assert_empty db[:assumption_links].all
        assert_empty db[:assumption_sees].all
    end

    def test_the_section_follows_facts
        ok("assume", BETA, "a — b")
        assert_includes markdown, "Facts:\n- F1: re2c is packaged — pkg " \
                                  "search re2c\n\nAssumptions:\n- A1 [open] " \
                                  "a — check: b\n\nDecisions:"
    end

    def test_a_new_one_needs_its_check_and_no_settling
        assert_refused("assume", BETA, "no dash", "ends with — and how")
        assert_refused("assume", BETA, "a — b", "--refuted-by", "F1",
                       "name an assumption")
    end

    def test_a_new_one_links_only_what_the_ledger_holds
        assert_refused("assume", BETA, "a — b", "--for", "P1,D1",
                       "--for: D1 is not a piece or question")
        assert_refused("assume", BETA, "a — b", "--for", "P7",
                       "--for: P7 is not a piece or question")
        assert_refused("assume", BETA, "a — b", "--see", "O1",
                       "--see: O1 is not a constraint, criterion, fact")
        assert_refused("assume", BETA, "a — b", "--see", "",
                       "--see is empty")
    end

    def test_an_assumption_is_undone_and_its_number_never_given_again
        ok("assume", BETA, "a — b", "--for", "P1", "--see", "F1")
        ok("undo", BETA)
        assert_empty db[:assumptions].all
        assert_empty db[:assumption_links].all
        assert_equal "A2", ok("assume", BETA, "c — d").lines.first.chomp
    end

    def test_a_dry_run_writes_nothing
        before = state
        out = ok("assume", BETA, "a — b", "--dry-run")
        assert_includes out, "+- A1 [open] a — check: b"
        assert_equal before, state
    end

    def test_show_gives_an_assumption_and_the_json_its_links
        ok("assume", BETA, "a — b", "--for", "P1,O1", "--see", "F1")
        assert_includes ok("show", BETA, "A1"), "state: open\nfact: \n" \
                                                "see: F1\nfor: P1 | O1"
        item = JSON.parse(ok("show", BETA, "A1", "--json"))["item"]
        assert_equal %w[P1 O1], item["for"]
    end

    def test_the_status_line_names_the_open_ones_after_blocked
        ok("assume", BETA, "a — b")
        ok("assume", BETA, "c — d")
        ok("assume", BETA, "e — f")
        ok("assume", BETA, "A2", "--confirmed-by", "F1")
        ok("piece", BETA, "P1", "--status", "blocked")
        assert_includes ok("status", BETA),
                        "blocked: P1 · assuming: A1, A3 · waiting on you"
    end
end

# `assume PATH A<n> --confirmed-by F<n> | --refuted-by F<n> | --for IDS
# | --reopen`: settled by a fact, relinked, reopened.
class AssumeMarkTest < AssumeCase
    def setup
        super
        ok("assume", BETA, "a — b", "--for", "P1")
    end

    def test_confirmed_and_refuted_name_the_fact
        ok("assume", BETA, "c — d")
        assert_includes ok("assume", BETA, "A1", "--confirmed-by", "F1"),
                        "- A1 [confirmed] a — check: b — for: P1 — by: F1"
        assert_includes ok("assume", BETA, "A2", "--refuted-by", "F1"),
                        "- A2 [refuted] c — check: d — by: F1"
        doc = JSON.parse(ok("show", BETA, "--json"))
        assert_equal(%w[F1 F1], doc["assumptions"].map { it["fact"] })
    end

    def test_reopen_clears_the_fact
        ok("assume", BETA, "A1", "--confirmed-by", "F1")
        assert_includes ok("assume", BETA, "A1", "--reopen"),
                        "- A1 [open] a — check: b — for: P1\n"
        assert_equal [["open", nil]],
                     db[:assumptions].select_map(%i[state fact_id])
    end

    def test_for_replaces_the_links
        assert_includes ok("assume", BETA, "A1", "--for", "O1"),
                        "- A1 [open] a — check: b — for: O1"
        assert_equal 1, db[:assumption_links].count
    end

    def test_a_fact_settles_it_and_nothing_else
        assert_refused("assume", BETA, "A1", "--confirmed-by", " ",
                       "--confirmed-by is empty")
        assert_refused("assume", BETA, "A1", "--confirmed-by", "seen",
                       "takes a fact, F<n>")
        assert_refused("assume", BETA, "A1", "--confirmed-by", "F9",
                       "F9 is not a fact of this ledger")
        assert_refused("assume", BETA, "A1", "--confirmed-by", "F1",
                       "--refuted-by", "F1", "give one of")
    end

    def test_the_other_refusals
        assert_refused("assume", BETA, "A9", "--reopen",
                       "A9 is not an assumption of this ledger")
        assert_refused("assume", BETA, "A1", "--for", "", "--for is empty")
        assert_refused("assume", BETA, "A1", "--see", "F1",
                       "--see goes with a new assumption")
        assert_refused("assume", BETA, "A1", "--reopen", "A1 is open already")
    end

    def test_a_settled_one_is_reopened_before_it_is_settled_again
        ok("assume", BETA, "A1", "--refuted-by", "F1")
        assert_refused("assume", BETA, "A1", "--confirmed-by", "F1",
                       "A1 is refuted already; --reopen it first")
        assert_refused("assume", BETA, "A1", "--refuted-by", "F1",
                       "A1 is refuted already")
    end

    # Only a hand or an old write settles one without its fact: the write
    # path refuses it, and `check` fails it when it is there.
    def test_a_write_settling_one_without_its_fact
        assert_raises(Ledger::Worse) { hand_settle(checks: Ledger::Checks) }
        hand_settle
        assert_includes cli("check", BETA)[1],
                        "FAIL assumptions-settled -- A1 confirmed without " \
                        "its fact"
    end

    # A1 confirmed by a write of its own, no fact named.
    def hand_settle(**)
        Ledger::Write.run(@journal, BETA, "hand", [], **) do |change|
            change.update(:assumptions, change.resolve("A1").last[:id],
                          state: "confirmed")
        end
    end

    def test_refuting_what_a_piece_in_flight_rests_on_fails_the_check
        ok("assume", BETA, "A1", "--refuted-by", "F1")
        code, out, = cli("check", BETA)
        assert_equal 1, code
        assert_includes out, "FAIL assumptions-refuted -- P1 rests on A1 " \
                             "(refuted)"
        ok("piece", BETA, "P1", "--status", "dropped")
        refute_includes ok("check", BETA), "FAIL assumptions-refuted"
    end
end
