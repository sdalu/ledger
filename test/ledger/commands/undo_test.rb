# frozen_string_literal: true

require_relative "helper"

# What `undo` tests share: a fact to revert, a question to answer.
class UndoCase < CommandCase
    PNG = "\x89PNG\x00\xFF".b

    def fact(text = "a — b") = ok("fact", BETA, text).lines.first.chomp
    def last_event = db[:events].order(:id).last

    def ask(*argv)
        ok("ask", BETA, "Which?", "--title", "Palette choice", "--problem",
           "p", "--risk", "2/10 — r", *argv)
    end
end

# `undo`: the last item-changing event reverted in an event of its own,
# one level; what the inbox holds is never reverted.
class UndoTest < UndoCase
    def test_the_last_event_is_reverted_and_said
        fact
        event = last_event
        out = ok("undo", BETA)
        assert_equal "undone: #{BETA} is back as it was before " \
                     "E#{event[:id]}", out.lines.first.chomp
        assert_match(/\AStatus \(Build the thing\) — /, out.lines.last)
        assert_equal 0, db[:facts].count
    end

    def test_the_undo_is_an_event_naming_what_it_reverted
        fact
        event = last_event
        ok("undo", BETA)
        assert_equal ["undo", event[:id], "undid E#{event[:id]}"],
                     last_event.values_at(:command, :undoes, :summary)
    end

    def test_an_id_undone_is_never_given_again
        fact
        ok("undo", BETA)
        assert_equal "F2", fact
    end

    def test_one_level_only
        fact
        fact("c — d")
        ok("undo", BETA)
        assert_equal 1, db[:facts].count
        assert_refused("undo", BETA, "nothing to undo")
    end

    def test_a_ledger_no_event_changed_has_nothing_to_undo
        code, _out, err = cli("undo", JournalTest::ADDRESS)
        assert_equal 2, code
        assert_includes err, "undo: nothing to undo"
    end

    def test_the_event_that_made_the_ledger_is_not_undone
        assert_refused("undo", BETA, "undo: nothing to undo")
        assert_equal 1, db[:goals].count
    end

    def test_inbox_and_take_events_are_passed_over
        fact
        Ledger::Inbox.append(@journal, BETA, [{ "text" => "hi" }],
                             actor: "cli")
        ok("take", BETA, "N1")
        ok("undo", BETA)
        assert_equal 0, db[:facts].count
        refute_nil db[:inbox_entries].get(:taken_id)
    end

    def test_a_taken_entry_stays_taken_when_its_answer_is_undone
        ask("--no-picture", "w")
        Ledger::Inbox.append(@journal, BETA, [{ "ref" => "O1", "text" => "x" }],
                             actor: "cli")
        ok("answer", BETA, "O1", "--decision", "warm", "--take", "N1")
        ok("undo", BETA)
        assert_nil db[:questions].get(:closed_at)
        assert_equal 0, db[:decisions].count
        refute_nil db[:inbox_entries].get(:taken_id)
    end

    def test_a_dry_run_prints_the_diff_and_writes_nothing
        fact
        before = state
        out = ok("undo", BETA, "--dry-run")
        assert_includes out, "dry run: nothing written"
        refute_includes out, "undone:"
        assert_equal before, state
    end

    def test_undo_needs_only_its_address
        assert_refused("undo", "usage: ledger undo PATH")
        assert_refused("undo", BETA, "x", "usage: ledger undo PATH")
    end
end

# `undo` and the rows: a row changed since, a deleted row back, a rule
# the revert would break, the blobs of a mockup.
class UndoRowsTest < UndoCase
    def test_a_row_changed_since_is_refused
        fact
        db[:facts].update(text: "edited by hand")
        assert_refused("undo", BETA, "facts row 1 changed since E")
        assert_equal 1, db[:facts].count
    end

    def test_a_deleted_row_comes_back_under_its_id
        ask("--no-picture", "w", "--choices",
            "A = a; x | B = b; y | C = c; z", "--recommend", "A, cheaper")
        ok("choice", BETA, "O1", "--drop", "B")
        ids = db[:question_choices].select_map(:id)
        ok("undo", BETA)
        assert_equal 3, db[:question_choices].count
        assert_includes db[:question_choices].select_map(:id), ids.first
    end

    def test_a_link_comes_back_with_the_event_that_wrote_it
        fact
        ok("decide", BETA, "keep it", "--by", "me", "--rests-on", "F1")
        written = db[:links].get(:event_id)
        Ledger::Write.run(@journal, BETA, "unlink", []) do |change|
            change.delete(:links, db[:links].get(:id))
        end
        ok("undo", BETA)
        assert_equal [written], db[:links].select_map(:event_id)
    end

    # An edge written by hand: X rests on F.
    def edge(decision, fact)
        db[:links].insert(ledger_id: @beta, kind: "rests_on", from_kind: "X",
                          from_row: decision, to_kind: "F", to_row: fact,
                          event_id: last_event[:id])
    end

    def test_a_revert_that_breaks_a_rule_is_refused
        ok("decide", BETA, "keep it", "--by", "me")
        fact
        edge(db[:decisions].get(:id), db[:facts].get(:id))
        assert_refused("undo", BETA, "undo: refused, links -- ")
        assert_equal 1, db[:facts].count
    end

    def test_an_undone_mockup_puts_back_the_question_and_keeps_the_blobs
        ask("--no-picture", "w")
        file = File.join(@dir, "shot.png")
        File.binwrite(file, PNG)
        ok("mockup", BETA, file, "--question", "O1")
        ok("undo", BETA)
        assert_empty db[:question_pictures].all
        assert_equal [PNG], db[:pictures].select_map(:bytes).map(&:to_s)
                                         .map(&:b)
    end
end

# undo of a piece's picture.
class UndoPiecePictureTest < CommandCase
    def test_an_undone_piece_picture_is_taken_away
        ok("piece", BETA, "new", "--title", "Fix the reorder", "--route",
           "sonnet, effort: low")
        file = File.join(@dir, "before.png")
        File.binwrite(file, "png")
        ok("mockup", BETA, file, "--piece", "P1", "--before")
        ok("undo", BETA)
        assert_empty db[:piece_pictures].all
        assert_equal ["before.png"], db[:pictures].select_map(:name)
    end
end
