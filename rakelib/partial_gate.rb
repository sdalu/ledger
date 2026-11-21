# frozen_string_literal: true

# What `rake gate:partial` checks for a set of changed files: the tests
# that name them, the Ruby files rubocop reads, whether a page changed,
# and the Ruby files no test names -- said, never passed over. The full
# `rake` still decides before a commit: a test that loads the whole app
# can depend on a file without naming it.
module PartialGate
    RUBY = /(\.rb|\.rake|\.ru|\ARakefile)\z/
    TESTS = %r{\Atest/.*_test\.rb\z}
    PAGE = %r{\A(views/|public/|lib/ledger_viewer/render/)}
    LINTED = %r{\A(lib|test|rakelib|config)/|\A(Rakefile|config\.ru)\z}
    VIEWER = %r{\A(lib/ledger_viewer|views|public)/|\Aconfig\.ru\z}

    # The selection for CHANGED (paths relative to ROOT, deleted ones
    # dropped): tests, linted, page (true when a page file changed) and
    # uncovered (Ruby source files no selected test names).
    Selection = Data.define(:tests, :linted, :page, :uncovered)

    module_function

    def select(root, changed)
        present = changed.uniq.select { File.file?(File.join(root, it)) }
        named = named_tests(root, present)
        Selection.new(tests: tests(present, named),
                      linted: present.select { linted?(it) },
                      page: present.any? { it.match?(PAGE) },
                      uncovered: uncovered(named))
    end

    def tests(present, named)
        (present.grep(TESTS) + named.values.flatten).uniq.sort
    end

    # The Ruby source files among NAMED that no test names.
    def uncovered(named)
        named.select { |path, tests| source?(path) && tests.empty? }.keys
    end

    # Each changed path with the tests that name it; a viewer file no
    # test names gets every viewer test, which loads the whole app.
    def named_tests(root, present)
        all = Dir.chdir(root) { Dir.glob("test/**/*_test.rb") }.sort
        present.to_h do |path|
            tests = tests_for(root, all, path)
            tests = viewer_tests(root, all) if tests.empty? && viewer?(path)
            [path, tests]
        end
    end

    def viewer?(path) = path.match?(VIEWER)

    # The tests that load the viewer through test_helper.
    def viewer_tests(root, all)
        all.select do |test|
            File.read(File.join(root, test)).include?(%(require "test_helper"))
        end
    end

    # A Ruby file the full rubocop run reads.
    def linted?(path) = path.match?(RUBY) && path.match?(LINTED)

    # A Ruby source file outside test/: one a test should cover.
    def source?(path) = path.end_with?(".rb") && !path.start_with?("test/")

    # The tests named after PATH's stem, or requiring it by path.
    def tests_for(root, all, path)
        return [] unless source?(path)

        stem = File.basename(path, ".rb")
        feature = path.delete_prefix("lib/").delete_suffix(".rb")
        all.select do |test|
            File.basename(test) == "#{stem}_test.rb" ||
                File.read(File.join(root, test))
                    .include?(%(require "#{feature}"))
        end
    end
end
