# frozen_string_literal: true

require "digest"
require "fileutils"

require_relative "helper"

# What the `mockup` tests share: an open question and files to place.
class MockupCase < CommandCase
    PNG = "\x89PNG\r\n\x00\xFF".b

    def setup
        super
        ok("ask", BETA, "Which palette wins?", "--title", "Palette choice",
           "--problem", "colours clash", "--risk", "2/10 — a redraw",
           "--no-picture", "words alone")
        @src = File.join(@dir, "src")
        FileUtils.mkdir_p(@src)
    end

    def file(name, bytes = PNG)
        File.join(@src, name).tap do |path|
            FileUtils.mkdir_p(File.dirname(path))
            File.binwrite(path, bytes)
        end
    end

    def mockup(*) = ok("mockup", BETA, *, "--question", "O1")

    def refused(*, message)
        assert_refused("mockup", BETA, *, "--question", "O1", message)
    end

    def line = markdown.lines.grep(/\A- O1:/).first

    def names = db[:question_pictures].order(:position).select_map(:name)
end

# `mockup`: files stored as pictures, a name shown on an open question.
class MockupTest < MockupCase
    def test_a_file_is_printed_with_its_question_and_the_viewer
        out = mockup(file("shot.png"))
        id = Digest::SHA1.hexdigest(BETA)[0, 10]
        assert_equal ["placed shot.png",
                      "O1: Palette choice: Which palette wins? — problem: " \
                      "colours clash — risk: 2/10 — a redraw — mockup: " \
                      "shot.png",
                      "viewer: /l/#{id} (the mockup at /m/#{id}/shot.png)"],
                     out.lines(chomp: true)
        assert_includes line, "— mockup: shot.png"
    end

    def test_a_file_is_stored_byte_for_byte
        mockup(file("shot.png"))
        row = db[:pictures].join(:picture_blobs, sha256: :sha256).first
        assert_equal ["shot.png", "", "image/png", PNG],
                     [row[:name], row[:path], row[:type], row[:bytes].to_s.b]
    end

    def test_the_mockup_is_one_event
        mockup(file("shot.png"))
        assert_equal ["mockup", "placed shot.png"],
                     db[:events].order(:id).last.values_at(:command, :summary)
    end

    def test_nothing_is_written_on_a_disk
        shot = file("shot.png")
        before = Dir.glob("#{@dir}/**/*")
        mockup(shot)
        assert_equal before, Dir.glob("#{@dir}/**/*")
    end

    def test_a_directory_is_one_name_with_a_row_per_file
        file("mock/index.html", "<p>")
        file("mock/css/s.css", "p{}")
        out = mockup(File.join(@src, "mock"))
        assert_equal ["placed mock/css/s.css", "placed mock/index.html"],
                     out.lines(chomp: true).first(2)
        assert_match(%r{\(the mockup at /m/\w+/mock/index.html\)\n\z}, out)
        assert_equal ["mock"], names
    end

    def test_a_directory_keeps_each_files_path_and_type
        file("mock/index.html", "<p>")
        file("mock/css/s.css", "p{}")
        mockup(File.join(@src, "mock"))
        assert_equal [["mock", "css/s.css", "text/css; charset=utf-8"],
                      ["mock", "index.html", "text/html; charset=utf-8"]],
                     db[:pictures].order(:path).select_map(%i[name path type])
    end

    def test_a_second_picture_is_added_beside_the_first
        mockup(file("a.png"))
        mockup(file("b.png"))
        assert_equal %w[a.png b.png], names
        assert_includes line, "— mockup: a.png — mockup: b.png"
    end

    def test_replace_swaps_the_pictures_and_keeps_the_old_blobs
        mockup(file("a.png"))
        mockup(file("b.png"), "--replace")
        assert_equal ["b.png"], names
        assert_equal %w[a.png b.png], db[:pictures].order(:id).select_map(:name)
    end

    def test_a_pending_picture_gives_way
        ok("piece", BETA, "new", "--title", "Draw the mockup", "--route",
           "haiku, effort: low")
        ok("ask", BETA, "Which font?", "--title", "Font choice", "--problem",
           "p", "--risk", "2/10 — r", "--pending", "P1")
        ok("mockup", BETA, file("f.png"), "--question", "O2")
        assert_equal [["f.png", nil]],
                     db[:question_pictures].where(question_id: 2)
                                           .select_map(%i[name pending_id])
        assert_empty db[:question_pictures].where(question_id: 1).all
    end
end

# `mockup` with several FILEs or a DIR: every name shown, a DIR by its pick.
class MockupSeveralTest < MockupCase
    def test_every_file_of_a_call_is_named_on_the_question
        mockup(file("a.png"), file("page.html", "<p>"), file("b.svg", "<svg/>"))
        assert_equal %w[a.png page.html b.svg], names
        assert_equal 3, db[:pictures].count
        assert_includes line, "— mockup: a.png — mockup: page.html — " \
                              "mockup: b.svg"
    end

    def test_the_viewer_line_names_each_file
        out = mockup(file("a.png"), file("b.svg", "<svg/>")).lines.last
        assert_includes out, "(the mockups at /m/"
        assert_equal %w[a.png b.svg], out.scan(%r{/m/\w+/([^,)]+)}).flatten
    end

    def test_a_pending_picture_takes_the_first_of_several
        ok("piece", BETA, "new", "--title", "Draw the mockup", "--route",
           "haiku, effort: low")
        ok("ask", BETA, "Which font?", "--title", "Font choice", "--problem",
           "p", "--risk", "2/10 — r", "--pending", "P1")
        ok("mockup", BETA, file("f.png"), file("g.png"), "--question", "O2")
        assert_equal [["f.png", nil], ["g.png", nil]],
                     db[:question_pictures].where(question_id: 2)
                                           .order(:position)
                                           .select_map(%i[name pending_id])
    end

    def test_replace_swaps_for_every_new_name
        mockup(file("a.png"))
        mockup(file("b.png"), file("c.png"), "--replace")
        assert_equal %w[b.png c.png], names
    end

    def test_name_may_name_the_one_directory
        file("d/index.html", "<p>")
        mockup(File.join(@src, "d"), "--name", "d")
        assert_equal ["d"], names
    end

    def test_a_directory_is_drawn_by_its_pick
        file("d1/index.html", "<p>")
        file("d1/other.html", "<p>")
        file("d2/one.htm", "<p>")
        file("d3/logo.svg", "<svg/>")
        file("d3/s.css", "p{}")
        out = mockup(File.join(@src, "d1"), File.join(@src, "d2"),
                     File.join(@src, "d3"))
        assert_equal %w[d1 d2 d3], names
        assert_match(%r{/d1/index.html, /m/\w+/d2/one.htm, /m/\w+/d3/logo.svg},
                     out)
    end
end

# `mockup` refused: each case leaves the journal as it was.
class MockupRefusalTest < MockupCase
    def test_a_picture_is_always_for_a_question
        assert_refused("mockup", BETA, file("a.png"),
                       "a picture is always for a question or a piece: add " \
                       "--question O<n> or --piece P<n>")
    end

    def test_the_question_must_be_open
        assert_refused("mockup", BETA, file("a.png"), "--question", "O7",
                       "O7 is not asked under Open in #{BETA}")
        assert_refused("mockup", BETA, file("a.png"), "--question", "P1",
                       "P1 is not asked under Open")
        ok("answer", BETA, "O1", "--decision", "warm")
        assert_refused("mockup", BETA, file("a.png"), "--question", "O1",
                       "O1 is not asked under Open")
    end

    def test_a_missing_file_and_a_symlink_and_nothing
        refused(File.join(@src, "gone.png"), "no such file or directory")
        File.symlink(file("real.png"), File.join(@src, "link.png"))
        refused(File.join(@src, "link.png"), "a symlink; copy the file itself")
        FileUtils.mkdir_p(File.join(@src, "empty"))
        refused(File.join(@src, "empty"), "nothing to place")
    end

    def test_a_name_the_line_cannot_spell_and_a_type_not_served
        refused(file("a b.png"), "use letters, digits, '.', '-', '_' only")
        refused(file("a.zip"), "does not serve this kind of file")
    end

    def test_name_must_be_among_those_placed
        refused(file("a.png"), "--name", "b.png",
                "--name b.png: not among the names placed (a.png)")
    end

    def test_name_is_refused_with_several_files
        refused(file("a.png"), file("b.png"), "--name", "b.png",
                "--name names one FILE or DIR, not several")
    end

    def test_no_page_or_image_to_pick
        file("m/one.html", "<p>")
        file("m/two.html", "<p>")
        refused(File.join(@src, "m"),
                "no index.html, single page or single image to pick in m")
        file("t/note.txt", "x")
        refused(File.join(@src, "t"),
                "no index.html, single page or single image to pick in t")
        refused(file("s.css", "p{}"),
                "no single page, image or text to pick in s.css")
    end

    def test_a_directory_of_pages_and_an_image_is_several_pages
        file("m/one.html", "<p>")
        file("m/two.html", "<p>")
        file("m/logo.png")
        refused(File.join(@src, "m"), "to pick in m")
    end

    def test_a_name_already_in_the_journal_is_refused
        mockup(file("a.png"))
        refused(file("a.png"), "a.png: already a picture of this ledger")
    end

    def test_a_path_and_a_file_are_needed
        assert_refused("mockup", BETA, "usage: ledger mockup PATH FILE...")
        assert_refused("mockup", "--question", "O1",
                       "usage: ledger mockup PATH FILE...")
    end
end

# `mockup --piece`: one file placed as a piece's before or after.
class MockupPieceTest < MockupCase
    def setup
        super
        ok("piece", BETA, "new", "--title", "Fix the reorder", "--route",
           "sonnet, effort: low")
    end

    def side(name, role, *)
        ok("mockup", BETA, file(name), "--piece", "P1", "--#{role}", *)
    end

    def sides = db[:piece_pictures].order(:position).select_map(%i[role name])

    def test_each_role_is_placed_before_first
        out = side("after.png", "after")
        side("before.png", "before")
        assert_equal [%w[before before.png], %w[after after.png]], sides
        assert_equal "placed after.png as P1 after", out.lines.first.chomp
        assert_equal %w[after.png before.png],
                     db[:pictures].order(:id).select_map(:name)
    end

    def test_replace_takes_the_earlier_side_away_and_keeps_its_blob
        side("b1.png", "before")
        side("b2.png", "before", "--replace")
        assert_equal [%w[before b2.png]], sides
        assert_equal %w[b1.png b2.png], db[:pictures].order(:id)
                                                     .select_map(:name)
    end

    def test_a_second_side_without_replace_is_refused
        side("b1.png", "before")
        assert_refused("mockup", BETA, file("b2.png"), "--piece", "P1",
                       "--before", "P1 has its before (b1.png); add " \
                                   "--replace to swap it")
    end

    def test_one_side_of_a_piece_and_not_a_question
        png = file("a.png")
        assert_refused("mockup", BETA, png, "--piece", "P1",
                       "--piece places one side: --before or --after")
        assert_refused("mockup", BETA, png, "--piece", "P1", "--before",
                       "--after", "--piece places one side")
        assert_refused("mockup", BETA, png, "--piece", "P1", "--before",
                       "--question", "O1",
                       "--question and --piece are exclusive")
        assert_refused("mockup", BETA, png, "--piece", "P9", "--before",
                       "no P9 under Pieces in #{BETA}")
    end

    def test_one_file_for_a_piece
        png = file("a.png")
        assert_refused("mockup", BETA, png, file("b.png"), "--piece", "P1",
                       "--before", "--piece places one file")
        file("dir/x.png")
        assert_refused("mockup", BETA, File.join(@src, "dir"), "--piece",
                       "P1", "--before", "--piece places one file, not a " \
                                         "directory")
        assert_refused("mockup", BETA, png, "--question", "O1", "--before",
                       "--before and --after are for --piece")
    end
end

# `mockup`: a picture's bytes stored once by their content.
class MockupBlobsTest < MockupCase
    OTHER = "\x89PNG\r\n\x00\x00".b

    def test_the_same_bytes_placed_twice_are_one_blob
        mockup(file("a.png"), file("b.png"))
        mockup(file("c.png"))
        assert_equal 3, db[:pictures].count
        assert_equal [Digest::SHA256.hexdigest(PNG)],
                     db[:picture_blobs].select_map(:sha256)
    end

    def test_replace_then_undo_brings_the_old_picture_back_unchanged
        mockup(file("a.png"))
        mockup(file("b.png", OTHER), "--replace")
        ok("undo", BETA)
        assert_equal ["a.png"], names
        assert_equal({ "a.png" => PNG, "b.png" => OTHER }, picture_bytes)
    end
end
