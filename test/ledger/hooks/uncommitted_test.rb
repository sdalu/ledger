# frozen_string_literal: true

require_relative "helper"

# uncommitted: a Stop names the files a session edited that a scratch git
# repository still shows as changed, once per set.
class UncommittedTest < HookTest
    SESSION = "s-1234"

    def setup
        super
        make_repo
        @address = File.join(@repo, "LEDGER.md")
        @journal.create_ledger(@address, project: "repo")
    end

    def make_repo
        @repo = File.realpath(Dir.mktmpdir("ledger-repo", @dir))
        git("init", "-q")
        git("config", "user.email", "t@example.invalid")
        git("config", "user.name", "T")
        @file = File.join(@repo, "a.txt")
        File.write(@file, "one\n")
        git("add", "a.txt")
        git("commit", "-q", "-m", "first")
    end

    def git(*) = system("git", "-C", @repo, *, exception: true)

    def edit(path)
        hook("edit-record", session_id: SESSION, tool_name: "Edit",
                            tool_input: { file_path: path })
    end

    def stop(**) = hook("uncommitted", cwd: @repo, session_id: SESSION, **)

    def dirty!
        File.write(@file, "two\n")
        edit(@file)
    end

    # A piece of the repository's ledger, with the words it awaits.
    def piece_in(status: "planned", awaits: [])
        Ledger::Write.run(@journal, @address, "import", []) do |change|
            id = piece(change, status:)
            awaits.each_with_index do |word, position|
                change.insert(:piece_awaits, piece_id: id, position:, word:,
                                             what: nil)
            end
        end
    end

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

    def test_a_piece_awaiting_commit_is_quiet
        dirty!
        piece_in(awaits: %w[commit])

        assert_equal Ledger::Hooks::Answer.pass, stop
    end

    def test_a_piece_out_is_quiet
        dirty!
        piece_in(status: "out")

        assert_equal Ledger::Hooks::Answer.pass, stop
    end

    def test_a_piece_awaiting_another_word_still_sends_the_stop
        dirty!
        piece_in(awaits: %w[deploy])

        assert_equal 2, stop.status
    end
end
