# frozen_string_literal: true

require "stringio"

require_relative "helper"
require "ledger/cli"

# What the commit-record tests share: a scratch git repository with a
# live ledger at its top, a branch of two commits to fast-forward to,
# and the hook run after a Bash command in a session whose id the
# ledger's commands carry.
module CommitRepo
    SESSION = "s-1234"
    GOAL = ["--goal", "build the thing now", "--title", "Build the thing",
            "--short", "build it", "--date", "2026-11-20"].freeze
    PIECE = ["--route", "sonnet, effort: low", "--status", "verified",
             "--verified-by", "me", "--evidence", "suite green",
             "--no-picture", "a wording change", "--problem", "not landed",
             "--risk", "2/10 — a small change"].freeze

    def setup
        super
        make_repo
        cli("new", @address, *GOAL)
        @session = ENV.fetch("CLAUDE_CODE_SESSION_ID", nil)
        ENV["CLAUDE_CODE_SESSION_ID"] = SESSION
    end

    def teardown
        ENV["CLAUDE_CODE_SESSION_ID"] = @session
        super
    end

    def make_repo
        @repo = File.realpath(Dir.mktmpdir("ledger-repo", @dir))
        git("init", "-q")
        git("config", "user.email", "t@example.invalid")
        git("config", "user.name", "T")
        commit("first")
        @base = git_out("branch", "--show-current").chomp
        @address = File.join(@repo, "LEDGER.md")
    end

    def git(*) = system("git", "-C", @repo, *, exception: true)
    def git_out(*) = IO.popen(["git", "-C", @repo, *], &:read)

    def commit(message)
        File.write(File.join(@repo, "a.txt"), "#{message}\n")
        git("add", "a.txt")
        git("commit", "-q", "-m", message)
    end

    def cli(*argv)
        out = StringIO.new
        err = StringIO.new
        code = Ledger::CLI.run(argv, out:, err:)
        assert_equal 0, code, err.string
    end

    # A verified piece awaiting WORDS.
    def piece(title, words)
        cli("piece", @address, "new", "--title", title, *PIECE,
            "--awaits", words)
    end

    # The commit word on PIECE, filed by the session ID.
    def word_by(id, piece)
        ENV["CLAUDE_CODE_SESSION_ID"] = id
        cli("word", @address, piece, "--word", "commit")
        ENV["CLAUDE_CODE_SESSION_ID"] = SESSION
    end

    # A branch of two commits, the base branch left where it was.
    def branch
        git("checkout", "-q", "-b", "feat")
        commit("second")
        commit("third")
        git("checkout", "-q", @base)
        @landed = git_out("rev-list", "--reverse", "--abbrev-commit",
                          "--abbrev=7", "#{@base}..feat").lines(chomp: true)
    end

    def seen = run_hook("git status")

    # The hook after COMMAND; it may write, which HookTest forbids.
    def run_hook(command, session: SESSION)
        answer = hook("commit-record", cwd: @repo, session_id: session,
                                       tool_name: "Bash",
                                       tool_input: { command: })
        @events_before = nil
        answer
    end

    # The fast-forward itself, then the hook that saw its command.
    def merge
        git("merge", "-q", "--ff-only", "feat")
        run_hook("git merge --ff-only feat")
    end

    attr_reader :landed

    def held(n)
        db[:piece_commits].where(piece_id: piece_id(n)).order(:position)
                          .select_map(:sha)
    end

    def piece_id(n) = db[:pieces].where(n:).get(:id)

    def context(answer)
        json(answer).dig("hookSpecificOutput", "additionalContext")
    end
end
