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
        row = db[:pictures].first
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
        assert_match(%r{\(the mockup at /m/\w+/mock\)\n\z}, out)
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

    def test_the_page_is_picked_among_many_files
        mockup(file("a.png"), file("page.html", "<p>"), file("s.css", "p{}"))
        assert_equal ["page.html"], names
        assert_equal 3, db[:pictures].count
    end

    def test_name_says_which_file_is_shown
        mockup(file("a.png"), file("b.png"), "--name", "b.png")
        assert_equal ["b.png"], names
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

# `mockup` refused: each case leaves the journal as it was.
class MockupRefusalTest < MockupCase
    def test_a_picture_is_always_for_a_question
        assert_refused("mockup", BETA, file("a.png"),
                       "a picture is always for a question: add --question")
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

    def test_no_single_page_image_or_text_to_pick
        refused(file("a.png"), file("b.png"),
                "say which name the question shows, with --name (a.png, b.png)")
        file("m/one.html", "<p>")
        file("m/two.html", "<p>")
        refused(File.join(@src, "m"), "--name", "m",
                "no single page, image or text to pick in m")
        refused(file("s.css", "p{}"), "--name", "s.css",
                "no single page, image or text to pick in s.css")
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
