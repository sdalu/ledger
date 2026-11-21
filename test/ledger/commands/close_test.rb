# frozen_string_literal: true

require_relative "helper"

# `close`: a finished ledger leaves the live ones, its row kept.
class CloseTest < CommandCase
    def finish
        ok("criterion", BETA, "D1", "--met", "seen")
    end

    def test_an_unfinished_ledger_is_not_closed
        before = state
        code, out, err = cli("close", BETA)
        assert_equal 1, code
        assert_includes out, "FAIL final-criteria -- D1 unmarked"
        assert_includes err, "#{BETA}: not closed; --final fails"
        assert_equal before, state
        assert_nil db[:ledgers].where(id: @beta).get(:closed_at)
    end

    def test_a_pending_viewer_entry_blocks_the_close
        finish
        db[:inbox_entries].insert(ledger_id: @beta, n: 1, at: "2026-11-21",
                                  payload: "{}")
        code, out, = cli("close", BETA)
        assert_equal 1, code
        assert_includes out,
                        "FAIL inbox -- the user's entries not filed yet: N1"
        assert_nil db[:ledgers].where(id: @beta).get(:closed_at)
    end

    # The viewer's Close, an entry with ref close: shown to the session
    # with the command that files it, taken in the close's own event.
    def test_the_close_asked_from_the_viewer_is_taken_by_the_close
        finish
        Ledger::Inbox.append(@journal, BETA, [{ "ref" => "close",
                                                "text" => "" }],
                             actor: "viewer:anna")
        assert_includes ok("inbox", BETA), "the word to close the ledger"
        out = ok("close", BETA, "--take", "N1")

        assert_includes out, "closed: #{BETA}"
        taken = db[:inbox_entries].where(ledger_id: @beta).get(:taken_id)
        assert_equal db[:events].where(ledger_id: @beta).max(:id), taken
    end

    # A close refused leaves the entry pending: the take was in the
    # write that did not happen.
    def test_a_refused_close_takes_nothing
        Ledger::Inbox.append(@journal, BETA, [{ "ref" => "close",
                                                "text" => "" }],
                             actor: "viewer:anna")
        code, out, = cli("close", BETA, "--take", "N1")

        assert_equal 1, code
        assert_includes out, "FAIL final-criteria"
        assert_nil db[:inbox_entries].where(ledger_id: @beta).get(:taken_id)
    end

    def test_a_closed_ledger_frees_its_address_and_carries_its_noticed_lines
        ok("noticed", BETA, "side thing")
        finish
        out = ok("close", BETA)
        assert_equal ["after action: nothing returned, blocked or stalled",
                      "closed: #{BETA} (L#{@beta})",
                      "noticed, to carry: 1", "- side thing"],
                     out.lines(chomp: true)
        refute_nil db[:ledgers].where(id: @beta).get(:closed_at)
        assert_equal 2, cli("status", BETA)[0]
        ok("new", BETA, *GOAL)
    end
end

# The after-action block of `close`, on BETA built with the commands,
# each event's time set by hand (minutes from zero): P1 returned for
# depth, P2 returned by a write that records no cause, P3 blocked once,
# P4 out 150 minutes; O1 answered after 12 minutes, O2 after 126; X2
# by me.
class CloseAfterActionTest < CommandCase
    DONE = ["--status", "verified", "--verified-by", "me",
            "--evidence", "tests pass"].freeze
    OUT = ["--status", "out", "--session", "s1"].freeze
    NEW = ["new", "--title", "Build a part", "--route",
           "opus, effort: high"].freeze
    BLOCK = ["after action:", "returned: P1 (depth), P2 (unrecorded)",
             "blocked: P3", "stalled: P4 (2.5 h)",
             "answered: O1 12 min, O2 2.1 h", "by me: X2"].freeze

    def setup
        super
        @session = ENV.delete("CLAUDE_CODE_SESSION_ID")
        4.times { ok("piece", BETA, *NEW) }
        pieces
        questions
    end

    def teardown
        ENV.delete("CLAUDE_CODE_SESSION_ID")
        ENV["CLAUDE_CODE_SESSION_ID"] = @session if @session
        super
    end

    def pieces
        returns
        at(0, "piece", "P3", "--status", "blocked")
        at(20, "piece", "P3", *DONE)
        at(0, "piece", "P4", *OUT)
        at(150, "piece", "P4", *DONE)
    end

    # P1 back to planned for depth, P2 with no cause recorded.
    def returns
        at(0, "piece", "P1", *OUT)
        at(10, "piece", "P1", "--status", "planned", "--cause", "depth")
        at(20, "piece", "P1", *OUT)
        at(30, "piece", "P1", *DONE)
        at(0, "piece", "P2", *OUT)
        unrecorded(20)
        at(30, "piece", "P2", *OUT)
        at(40, "piece", "P2", *DONE)
    end

    def questions
        ask(0, "Which palette wins?", "Palette choice")
        at(12, "answer", "O1", "--decision", "warm")
        ask(60, "Which font reads best?", "Font choice")
        at(70, "decide", "serif first", "--by", "me")
        at(186, "answer", "O2", "--decision", "serif")
    end

    def ask(minute, detail, title)
        at(minute, "ask", detail, "--title", title, "--problem",
           "nothing chosen yet", "--risk", "2/10 — a redraw",
           "--no-picture", "words alone")
    end

    # P2 back to planned by a write that records no cause.
    def unrecorded(minute)
        id = db[:pieces].where(ledger_id: @beta, n: 2).get(:id)
        Ledger::Write.run(@journal, BETA, "piece", []) do |change|
            change.update(:pieces, id, status: "planned", claimed_by: nil)
        end
        stamp(minute)
    end

    # The command run, BETA put after its name, its event at MINUTE.
    def at(minute, command, *argv)
        ok(command, BETA, *argv)
        stamp(minute)
    end

    def stamp(minute)
        db[:events].where(id: db[:events].max(:id))
                   .update(at: minute * 60_000)
    end

    def test_the_block_comes_before_the_closed_line
        ok("criterion", BETA, "D1", "--met", "seen")
        assert_equal [*BLOCK, "closed: #{BETA} (L#{@beta})"],
                     ok("close", BETA).lines(chomp: true)
    end

    # O3 closed by a write that links no decision to it.
    def test_a_question_closed_without_an_answer_record_says_so
        ask(200, "Which size fits?", "Size choice")
        id = db[:questions].where(ledger_id: @beta, n: 3).get(:id)
        Ledger::Write.run(@journal, BETA, "ask", []) do |change|
            change.update(:questions, id, closed_at: Ledger::Write.now)
        end
        ok("criterion", BETA, "D1", "--met", "seen")
        assert_includes ok("close", BETA).lines(chomp: true),
                        "answered: O1 12 min, O2 2.1 h, O3 (no answer record)"
    end

    def test_a_refused_close_prints_no_block
        code, out, = cli("close", BETA)
        assert_equal 1, code
        refute_includes out, "after action:"
    end
end

# `close --abandon`: an unfinished ledger closed in one event, its open
# pieces dropped and its open questions closed by the user's decision,
# the history kept; a close is not undone.
class CloseAbandonTest < CommandCase
    NEW = ["new", "--title", "Build a part", "--route",
           "opus, effort: high"].freeze
    DONE = ["--status", "verified", "--verified-by", "me",
            "--evidence", "tests pass"].freeze

    def setup
        super
        @session = ENV.delete("CLAUDE_CODE_SESSION_ID")
        5.times { ok("piece", BETA, *NEW) }
        ok("piece", BETA, "P2", "--status", "out", "--session", "s1")
        ok("piece", BETA, "P3", "--status", "blocked")
        ok("piece", BETA, "P4", *DONE)
        ok("ask", BETA, "Which palette wins?", "--title", "Palette choice",
           "--problem", "nothing chosen yet", "--risk", "2/10 — a redraw",
           "--no-picture", "words alone")
    end

    def teardown
        ENV.delete("CLAUDE_CODE_SESSION_ID")
        ENV["CLAUDE_CODE_SESSION_ID"] = @session if @session
        super
    end

    def statuses
        db[:pieces].where(ledger_id: @beta).order(:n).select_map(:status)
    end

    def last_argv = JSON.parse(db[:events].reverse(:id).get(:argv))

    def test_one_event_closes_it_and_its_argv_holds_the_flag
        events = db[:events].count
        out = ok("close", BETA, "--abandon")

        assert_includes out.lines(chomp: true),
                        "abandoned: #{BETA} (L#{@beta})"
        assert_equal [events + 1, true],
                     [db[:events].count, last_argv.include?("--abandon")]
    end

    def test_the_open_pieces_are_dropped_and_the_questions_closed
        ok("close", BETA, "--abandon")

        assert_equal %w[dropped dropped dropped verified dropped], statuses
        refute_nil db[:questions].where(ledger_id: @beta).get(:closed_at)
        decision = db[:decisions].where(ledger_id: @beta).first
        assert_equal ["O1: abandoned with the ledger", "user", "O1"],
                     decision.values_at(:body, :by, :subject)
    end

    # As `word --word drop` drops one: a dropped piece awaits nothing.
    def test_a_dropped_piece_keeps_no_awaits_nor_scope
        ok("piece", BETA, "P5", "--problem", "it waits", "--risk",
           "4/10 — a bad push", "--awaits", "start, other (the shots)",
           "--scope", "start = begin it | other = look at them")
        refute_empty db[:piece_awaits].all
        ok("close", BETA, "--abandon")

        assert_empty db[:piece_awaits].all
        assert_empty db[:piece_scopes].all
    end

    def test_the_history_stays_and_nothing_undoes_it
        ok("close", BETA, "--abandon")
        before = state

        assert_equal 2, cli("undo", BETA)[0]
        assert_equal before, state
        assert_operator db[:events].where(ledger_id: @beta).count, :>, 1
    end

    def test_an_entry_pending_still_refuses_it
        Ledger::Inbox.append(@journal, BETA, [{ "text" => "wait" }],
                             actor: "viewer:anna")
        before = state
        code, out, err = cli("close", BETA, "--abandon")

        assert_equal 1, code
        assert_includes out, "FAIL inbox -- the user's entries not filed yet"
        refute_includes out, "final-"
        assert_includes err, "not abandoned; an entry is pending"
        assert_equal before, state
    end

    # The viewer's Abandon: shown with the command that files it, taken
    # in the close's own event.
    def test_the_abandon_asked_from_the_viewer_is_taken
        Ledger::Inbox.append(@journal, BETA, [{ "ref" => "abandon",
                                                "text" => "" }],
                             actor: "viewer:anna")
        assert_includes ok("inbox", BETA),
                        "the word to abandon the ledger: ledger close PATH " \
                        "--abandon --take N<n>"
        ok("close", BETA, "--abandon", "--take", "N1")
        taken = db[:inbox_entries].where(ledger_id: @beta).get(:taken_id)
        assert_equal db[:events].where(ledger_id: @beta).max(:id), taken
    end

    def test_show_tells_it_apart
        gamma = finished_gamma
        ok("close", BETA, "--abandon")

        assert_match(/\n\nabandoned: \d{4}-/, ok("show", "L#{@beta}"))
        assert_match(/\n\nclosed: \d{4}-/, ok("show", "L#{gamma}"))
    end

    def test_stats_tells_it_apart
        finished_gamma
        ok("close", BETA, "--abandon")

        assert_equal "closed ledgers: 1 finished, 1 abandoned",
                     ok("stats").lines(chomp: true).last
        assert_equal({ "finished" => 1, "abandoned" => 1 },
                     JSON.parse(ok("stats", "--json"))["closed"])
        refute JSON.parse(ok("stats", "L#{@beta}", "--json")).key?("closed")
    end

    # A second ledger, finished and closed; its id.
    def finished_gamma
        gamma = "/work/gamma/LEDGER.md"
        ok("new", gamma, *GOAL)
        ok("criterion", gamma, "D1", "--met", "seen")
        ok("close", gamma)
        db[:ledgers].where(place: "/work/gamma").get(:id)
    end
end
