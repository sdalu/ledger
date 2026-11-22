# frozen_string_literal: true

require_relative "uncommitted_repo"

# uncommitted: a Stop names the files a session edited that a scratch git
# repository still shows as changed, once per set.
class UncommittedTest < HookTest
    include UncommittedRepo

    def test_a_changed_file_is_named_once_for_a_set
        dirty!
        answer = stop

        assert_equal 2, answer.status
        assert_nil answer.out
        assert_equal "files you edited are uncommitted and no piece awaits " \
                     "commit: #{@file}; file one with --awaits commit " \
                     "(its scope naming them), or say why not\n",
                     "#{answer.err}\n"
        assert_equal Ledger::Hooks::Answer.pass, stop
    end

    def test_a_new_file_makes_a_new_set
        dirty!
        stop
        added = File.join(@repo, "b.txt")
        File.write(added, "x\n")
        edit(added)

        answer = stop

        assert_equal 2, answer.status
        assert_match "#{@file}, #{added}", answer.err
    end

    def test_the_retry_goes_through
        dirty!

        assert_equal Ledger::Hooks::Answer.pass, stop(stop_hook_active: true)
    end

    def test_a_clean_or_reverted_file_drops_out
        edit(@file)

        assert_equal Ledger::Hooks::Answer.pass, stop
        dirty!
        File.write(@file, "one\n")

        assert_equal Ledger::Hooks::Answer.pass, stop
    end

    def test_a_file_outside_a_repository_is_ignored
        outside = File.join(@dir, "loose.txt")
        File.write(outside, "x\n")
        edit(outside)

        assert_equal Ledger::Hooks::Answer.pass, stop
    end

    def test_no_live_ledger_is_quiet
        dirty!
        @journal.db[:ledgers].where(place: @repo).update(closed_at: 1)

        assert_equal Ledger::Hooks::Answer.pass, stop
    end

    def test_no_record_is_quiet
        File.write(@file, "two\n")

        assert_equal Ledger::Hooks::Answer.pass, stop
    end
end
