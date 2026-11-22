# frozen_string_literal: true

require_relative "helper"

# What the uncommitted tests share: a scratch git repository with a live
# ledger at its top, and a session whose edits are recorded.
module UncommittedRepo
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
end
