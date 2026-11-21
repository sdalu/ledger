# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../rakelib/partial_gate"

# What rake gate:partial selects for a set of changed files, on a tree
# of the test's own.
class PartialGateTest < Minitest::Test
    FILES = {
        "lib/ledger/foo.rb" => "",
        "lib/ledger/bar.rb" => "",
        "lib/ledger_viewer/render/card.rb" => "",
        "views/x.erb" => "",
        "README.md" => "",
        "test/ledger/foo_test.rb" => "",
        "test/uses_bar_test.rb" => %(require "ledger/bar"\n),
        "test/other_test.rb" => ""
    }.freeze

    def setup
        @root = Dir.mktmpdir("partial-gate")
        FILES.each do |path, text|
            FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
            File.write(File.join(@root, path), text)
        end
    end

    def teardown = FileUtils.rm_rf(@root)

    def pick(*changed) = PartialGate.select(@root, changed)

    def test_a_source_file_selects_the_test_named_after_it
        assert_equal ["test/ledger/foo_test.rb"],
                     pick("lib/ledger/foo.rb").tests
    end

    def test_a_source_file_selects_the_tests_requiring_it
        assert_equal ["test/uses_bar_test.rb"], pick("lib/ledger/bar.rb").tests
    end

    def test_a_changed_test_is_selected_itself
        assert_equal ["test/other_test.rb"], pick("test/other_test.rb").tests
    end

    def test_a_source_file_no_test_names_is_said
        File.write(File.join(@root, "lib/ledger/lone.rb"), "")
        selection = pick("lib/ledger/lone.rb", "README.md")

        assert_empty selection.tests
        assert_equal ["lib/ledger/lone.rb"], selection.uncovered
    end

    # A viewer test loads the whole app: a viewer file no test names
    # gets every one of them.
    def test_a_viewer_file_no_test_names_selects_the_viewer_tests
        File.write(File.join(@root, "test/page_test.rb"),
                   %(require "test_helper"\n))
        selection = pick("lib/ledger_viewer/render/card.rb")

        assert_equal ["test/page_test.rb"], selection.tests
        assert_empty selection.uncovered
        assert selection.page
    end

    def test_rubocop_reads_the_ruby_files_only_and_a_deleted_file_is_dropped
        selection = pick("lib/ledger/foo.rb", "views/x.erb", "README.md",
                         "lib/ledger/gone.rb")

        assert_equal ["lib/ledger/foo.rb"], selection.linted
        assert selection.page
    end

    def test_no_page_file_runs_no_browser
        refute pick("lib/ledger/foo.rb").page
    end
end
