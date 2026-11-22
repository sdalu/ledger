# frozen_string_literal: true

require "fileutils"

require_relative "helper"

# What the `prune-pictures` tests share: BETA's O1 once showed a.png,
# b.png (the same bytes as a.png) and c.png (bytes of its own), each by
# its own mockup; a --replace then took them away for d.png, which has
# the same bytes as a.png. So a, b and c are unused, the content of c
# is left alone, and the content of a and b is still d's. Every picture
# is placed 30 days ago.
class PruneCase < CommandCase
    PNG = "\x89PNG\r\n\x00\xFF".b
    OWN = "\x89PNG\r\n\x00\x01own".b
    DAY_MS = 86_400_000

    def setup
        super
        ask
        @src = File.join(@dir, "src")
        FileUtils.mkdir_p(@src)
        place("a.png")
        place("b.png")
        place("c.png", OWN)
        place("d.png", PNG, "--replace")
        %w[a.png b.png c.png d.png].each { age(it, 30) }
    end

    def place(name, bytes = PNG, *)
        ok("mockup", BETA, file(name, bytes), "--question", "O1", *)
    end

    def ask
        ok("ask", BETA, "Which palette wins?", "--title", "Palette choice",
           "--problem", "colours clash", "--risk", "2/10 — a redraw",
           "--no-picture", "words alone")
    end

    def file(name, bytes = PNG)
        File.join(@src, name).tap { File.binwrite(it, bytes) }
    end

    # The picture NAME's event moved to DAYS ago.
    def age(name, days)
        event = db[:pictures].where(name:).get(:event_id)
        db[:events].where(id: event)
                   .update(at: Ledger::Write.now - (days * DAY_MS))
    end

    def prune(*, confirmed: false)
        argv = ["prune-pictures", *]
        argv << "--confirmed" if confirmed
        cli(*argv)
    end

    def names = db[:pictures].order(:name).select_map(:name)

    def backups = Dir.glob("#{@journal.path}.before-prune-*")

    def totals = db.tables.to_h { [it, db[it].count] }
end

# `prune-pictures` without --confirmed: a listing, nothing written.
class PrunePicturesDryRunTest < PruneCase
    def test_a_dry_run_lists_each_unused_picture_and_writes_nothing
        before = totals
        bytes = File.binread(@journal.path)
        code, out, = prune
        assert_equal 0, code
        assert_equal %w[a.png b.png c.png], listed(out)
        assert_equal before, totals
        assert_equal bytes, File.binread(@journal.path)
        assert_empty backups
    end

    def test_a_line_says_ledger_owner_name_size_and_date
        placed = Time.at((Ledger::Write.now - (30 * DAY_MS)) / 1000)
                     .strftime("%F")
        out = prune[1]
        assert_equal "L#{@beta} O1 a.png #{PNG.bytesize} bytes placed " \
                     "#{placed}", out.lines.first.chomp
    end

    def listed(out) = out.lines.grep(/\AL\d/).map { it.split[2] }

    def test_the_totals_count_the_rows_the_contents_and_the_bytes
        _code, out, = prune
        assert_includes out, "would remove 3 picture rows, 1 stored " \
                             "contents, #{OWN.bytesize} bytes"
    end

    def test_a_picture_a_question_names_is_not_listed
        _code, out, = prune
        refute_includes out, "d.png"
    end

    def test_a_picture_a_choice_or_a_piece_names_is_not_listed
        db[:question_choices].insert(question_id: 1, position: 0, label: "A",
                                     picture: "a.png")
        piece = piece_serving(1).value
        db[:piece_pictures].insert(piece_id: piece, position: 0,
                                   role: "before", name: "b.png")
        assert_equal %w[c.png], listed(prune[1])
    end

    def test_a_picture_younger_than_the_age_is_not_listed
        age("b.png", 3)
        _code, out, = prune
        refute_includes out, "b.png"
        assert_includes out, "would remove 2 picture rows"
    end

    def test_older_moves_the_age
        age("b.png", 3)
        _code, out, = prune("--older", "2")
        assert_includes out, "b.png"
        _code, out, = prune("--older", "40")
        assert_includes out, "would remove 0 picture rows"
    end

    def test_a_ledger_id_limits_it
        ok("new", "/work/other/LEDGER.md", *GOAL)
        other = db[:ledgers].where(place: "/work/other").get(:id)
        _code, out, = prune("L#{other}")
        assert_includes out, "would remove 0 picture rows"
        _code, out, = prune("L#{@beta}")
        assert_includes out, "would remove 3 picture rows"
    end

    def test_an_unknown_ledger_and_a_bad_age_are_refused
        assert_refused("prune-pictures", "L999", "no ledger L999")
        assert_refused("prune-pictures", "beta", "is not a ledger id")
        assert_refused("prune-pictures", "--older", "-1", "not negative")
    end
end

# `prune-pictures --confirmed`: the backup, then the delete.
class PrunePicturesConfirmedTest < PruneCase
    def test_only_the_unused_pictures_are_removed
        code, out, = prune(confirmed: true)
        assert_equal 0, code
        assert_equal %w[d.png], names
        assert_includes out, "removed 3 picture rows, 1 stored contents"
        assert_equal ["d.png"], db[:question_pictures].select_map(:name)
    end

    def test_a_content_another_picture_shares_stays_and_a_lone_one_goes
        prune(confirmed: true)
        blobs = db[:picture_blobs].select_map(:bytes).map { it.to_s.b }
        assert_equal [PNG], blobs
        assert_equal db[:pictures].select_map(:sha256),
                     db[:picture_blobs].select_map(:sha256)
    end

    def test_a_content_no_picture_points_to_goes_too
        db[:picture_blobs].insert(sha256: "0" * 64, bytes: Sequel.blob("x"),
                                  size: 1)
        out = ok("prune-pictures", "--confirmed")
        assert_includes out, "stored contents"
        assert_equal 1, db[:picture_blobs].count
    end

    def test_a_younger_picture_stays
        age("c.png", 2)
        prune(confirmed: true)
        assert_equal %w[c.png d.png], names
        assert_equal 2, db[:picture_blobs].count
    end

    def test_the_backup_is_made_and_named_last_but_one
        out = prune(confirmed: true)[1]
        assert_equal ["backup: #{backups.first}"], out.lines.grep(/\Abackup/)
                                                      .map(&:chomp)
        assert_includes out.lines.last, "ledger vacuum shrinks the file"
    end

    def test_the_backup_holds_the_journal_as_it_was
        prune(confirmed: true)
        copy = Sequel.sqlite(backups.first)
        assert_equal 4, copy[:pictures].count
        copy.disconnect
    end

    def test_an_existing_backup_name_is_refused
        now = Time.new(2026, 11, 22, 10, 0, 0)
        name = Ledger::Backup.prune_path(@journal.path, at: now)
        File.write(name, "mine")
        # the refusal itself is recorded in outcomes, the rest stays
        before = totals.except(:outcomes)
        code, _out, err = at(now) { prune(confirmed: true) }
        assert_equal 2, code
        assert_includes err, "exists; nothing pruned"
        assert_equal "mine", File.read(name)
        assert_equal before, totals.except(:outcomes)
    end

    def test_nothing_to_prune_makes_no_backup
        prune(confirmed: true)
        out = ok("prune-pictures", "--confirmed")
        assert_equal "nothing to prune\n", out
        assert_equal 1, backups.size
    end

    def test_a_ledger_id_limits_it
        ok("new", "/work/other/LEDGER.md", *GOAL)
        other = db[:ledgers].where(place: "/work/other").get(:id)
        prune("L#{other}", confirmed: true)
        assert_equal %w[a.png b.png c.png d.png], names
    end

    # The block run with Time.now fixed at TIME.
    def at(time)
        Time.singleton_class.alias_method(:real_now, :now)
        Time.define_singleton_method(:now) { time }
        yield
    ensure
        Time.singleton_class.alias_method(:now, :real_now)
        Time.singleton_class.remove_method(:real_now)
    end
end

# An undo or restore that names a picture pruned in between: it works,
# and the picture is gone.
class PrunePicturesUndoTest < PruneCase
    # The replace undone, d.png pruned, the undo restored over.
    def restored
        mark = db[:events].order(:id).last[:id]
        ok("undo", BETA)
        prune(confirmed: true)
        ok("restore", BETA, "--to", "E#{mark}")
    end

    def test_a_restore_naming_a_pruned_picture_works
        restored
        assert_equal %w[a.png b.png c.png], names
        assert_equal ["d.png"], db[:question_pictures].select_map(:name)
    end

    def test_a_reader_finds_no_row_and_draws_nothing_for_it
        restored
        document = Ledger::Read.parse(JSON.generate(
                                          Ledger::Read.ledger(@journal, @beta)
                                      ))
        refute_includes document["pictures"].map { it["name"] }, "d.png"
        shown = document["questions"].first["pictures"].map { it["name"] }
        assert_equal ["d.png"], shown
    end
end
