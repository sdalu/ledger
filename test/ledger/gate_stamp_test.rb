# frozen_string_literal: true

require "rake"

require_relative "../support/hook_repo"

# The stamp a passing gate leaves for the tree it tested, and the rake
# tasks and the word that write it.
class GateStampTest < HookRepoCase
    def test_a_stamp_is_written_for_the_tree_tested
        tested = tree

        assert Ledger::GateStamp.write(@repo, tested)
        assert Ledger::GateStamp.stamped?(@repo, tested)
        assert_equal [tested], File.readlines(stamp_file, chomp: true)
    end

    def test_no_stamp_when_the_index_changed_during_the_run
        tested = tree
        stage("a.txt", "two\n")

        assert_nil Ledger::GateStamp.write(@repo, tested)
        refute File.exist?(stamp_file)
    end

    def test_the_last_fifty_are_kept
        trees = Array.new(52) { "#{it.to_s.rjust(2, "0")}#{"a" * 38}" }
        trees.each { Ledger::GateStamp.record(@repo, it) }

        assert_equal trees.last(50), Ledger::GateStamp.trees(@repo)
    end

    def test_the_word_stamps_and_refuses_a_stale_tree
        tested = tree
        code, out, = run_cli("gate-stamp", @repo, "--tree", tested)

        assert_equal [0, "stamped #{tested}\n"], [code, out]
        stage("a.txt", "three\n")
        _, out, err = run_cli("gate-stamp", @repo, "--tree", tested)

        assert_empty out
        assert_includes err, "nothing stamped"
    end

    def test_the_rake_tasks_stamp_a_run_that_left_the_index_alone
        out, = capture_io { run_stamp_tasks { nil } }

        assert_includes out, "gate stamp written"
        assert Ledger::GateStamp.stamped?(@repo, tree)
    end

    def test_the_rake_tasks_stamp_nothing_when_the_index_changed
        _, err = capture_io { run_stamp_tasks { stage("a.txt", "two\n") } }

        refute File.exist?(stamp_file)
        assert_includes err, "index changed during the run"
    end

    private

    # stamp:begin, the block (the gate's run), stamp:write, in @repo.
    def run_stamp_tasks
        Rake.application = Rake::Application.new
        load File.expand_path("../../rakelib/stamp.rake", __dir__)
        Dir.chdir(@repo) do
            Rake::Task["stamp:begin"].invoke
            yield
            Rake::Task["stamp:write"].invoke
        end
    end
end
