# frozen_string_literal: true

require "digest"

require_relative "ledger_commands"

# A ledger in the viewer's journal, for the tests of its page and of its
# pictures: gamma, one question open, made by `new` and `ask` as a
# session makes one.
module LedgerFixture
    GOAL = ["--goal", "port the parser to C23", "--title", "Port the parser",
            "--short", "port the parser", "--date", "2026-11-19"].freeze
    QUESTION = ["which?", "--title", "Which one", "--problem", "two",
                "--risk", "5/10 — meh", "--choices", "A = one | B = two",
                "--recommend", "A, simple",
                "--no-picture", "a choice of words"].freeze

    def setup
        super
        @ledger = File.join(@dir, "gamma/.claude/LEDGER.md")
        build_fixture
        @lid = Digest::SHA1.hexdigest(@ledger)[0, 10]
    end

    # What a test class builds: gamma; a class adds to it after super.
    def build_fixture
        ledger("new", *GOAL)
        ledger("ask", *QUESTION)
    end

    # `ledger WORD @ledger ARGS...` on the viewer's journal.
    def ledger(word, *) = LedgerCommands.run(@journal, word, @ledger, *)

    # FILES ({name => body}) written under a directory of the test, then
    # placed on O1 by `mockup`, one name per call, in their order.
    def place(files)
        root = File.join(@dir, "pictures")
        files.each do |name, body|
            file = File.join(root, name)
            FileUtils.mkdir_p(File.dirname(file))
            File.write(file, body)
        end
        files.keys.map { it.split("/").first }.uniq.each do |name|
            ledger("mockup", File.join(root, name), "--question", "O1")
        end
    end
end
