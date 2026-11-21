# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require_relative "helper"
require "ledger/pictures"

# The picking rule and the reading of a mockup's files.
class PicturesTest < Minitest::Test
    Item = Ledger::Pictures::Item

    def setup
        @dir = Dir.mktmpdir("ledger-pictures-test")
    end

    def teardown = FileUtils.rm_rf(@dir)

    def item(file) = Item.new(name: "m", path: file, type: "x", bytes: "")

    def pick(*files) = Ledger::Pictures.page(files.map { item(it) })&.path

    def test_the_only_page_is_the_one_opened
        assert_equal "a.html", pick("a.html", "s.css", "x.png")
        assert_equal "b.HTM", pick("b.HTM", "x.png")
    end

    def test_an_image_when_there_is_no_page_and_a_text_after_that
        assert_equal "x.png", pick("x.png", "s.css")
        assert_equal "n.txt", pick("n.txt", "s.css")
        assert_equal "x.svg", pick("x.svg", "n.txt")
    end

    def test_several_of_the_first_kind_or_none_is_no_page
        assert_nil pick("a.html", "b.html", "x.png")
        assert_nil pick("x.png", "y.jpg")
        assert_nil pick("s.css", "f.woff")
        assert_nil pick
    end

    def test_a_file_placed_alone_is_a_name_with_no_path
        file = File.join(@dir, "shot.png")
        File.binwrite(file, "\x00\xFF\x89".b)
        (item,) = Ledger::Pictures::Sources.new([file]).items
        assert_equal ["shot.png", "", "image/png", "\x00\xFF\x89".b],
                     [item.name, item.path, item.type, item.bytes]
        assert_equal Encoding::BINARY, item.bytes.encoding
    end

    def test_a_directory_is_one_name_with_a_row_per_file
        FileUtils.mkdir_p(File.join(@dir, "mock", "css"))
        File.write(File.join(@dir, "mock", "index.html"), "<p>")
        File.write(File.join(@dir, "mock", "css", "s.css"), "p{}")
        items = Ledger::Pictures::Sources.new([File.join(@dir, "mock/")]).items
        assert_equal([["mock", "css/s.css"], ["mock", "index.html"]],
                     items.map { [it.name, it.path] })
        assert_equal "mock/css/s.css", items.first.file
    end

    def refused(*sources)
        sources = sources.map { File.join(@dir, it) }
        assert_raises(Ledger::Refused) do
            Ledger::Pictures::Sources.new(sources).items
        end.message
    end

    def test_a_source_is_refused_before_any_is_read
        File.write(File.join(@dir, "ok.png"), "x")
        assert_includes refused("ok.png", "gone.png"), "no such file"
        FileUtils.mkdir(File.join(@dir, "empty"))
        assert_equal "nothing to place", refused("empty")
        File.write(File.join(@dir, "a b.png"), "x")
        assert_includes refused("a b.png"), "letters, digits"
        File.write(File.join(@dir, "x.zip"), "x")
        assert_includes refused("x.zip"), "does not serve this kind of file"
    end

    def test_symlinks_are_refused
        File.write(File.join(@dir, "real.png"), "x")
        File.symlink("real.png", File.join(@dir, "link.png"))
        assert_includes refused("link.png"), "a symlink; copy the file itself"
        FileUtils.mkdir(File.join(@dir, "d"))
        File.symlink("../real.png", File.join(@dir, "d", "l.png"))
        assert_includes refused("d"), "l.png: a symlink"
    end

    def test_two_files_of_one_name_are_refused
        FileUtils.mkdir_p(File.join(@dir, "a"))
        File.write(File.join(@dir, "a", "x.png"), "1")
        File.write(File.join(@dir, "x.png"), "1")
        FileUtils.mkdir_p(File.join(@dir, "b"))
        File.write(File.join(@dir, "b", "x.png"), "2")
        assert_includes refused("x.png", "a/x.png", "b/x.png"),
                        "x.png: placed twice"
    end
end
