# frozen_string_literal: true

require "fileutils"

require_relative "browser_fixture"
require_relative "ledger_commands"

# A ledger of one question with three options, for test/browser/
# choices.cjs: O1 has its own picture and pictures on A and C, none on
# B. Made by bin/ledger's words in the caller's journal, in one
# transaction; the pictures are copies of the main fixture's SVGs under
# names of their own, beside the ledger.
module ChoicesFixture
    GOAL = ["--goal", "an option shows what it does", "--title",
            "Options with pictures", "--short", "pictures per option",
            "--date", "2026-11-19"].freeze
    QUESTION = ["which layout wins?", "--title", "Layout choice",
                "--problem", "the page is cramped",
                "--risk", "2/10 — a redraw",
                "--choices", "A = wide | B = narrow | C = tall",
                "--recommend", "A, roomier",
                "--no-picture", "words alone"].freeze
    # [the picture's name, its source in the main fixture, its place].
    PICTURES = [["layout-before.svg", "reorder-before.svg", []],
                ["layout-a.svg", "reorder-after.svg", ["--choice", "A"]],
                ["layout-c.svg", "reorder-after.svg", ["--choice", "C"]]]
               .freeze

    def self.build(journal, address)
        run = lambda do |word, *args|
            LedgerCommands.run(journal, word, address, *args)
        end
        dir = File.join(File.dirname(address), "pictures")
        FileUtils.mkdir_p(dir)
        journal.transaction do
            run.call("new", *GOAL)
            run.call("ask", *QUESTION)
            PICTURES.each { place(run, dir, *it) }
        end
    end

    def self.place(run, dir, name, source, flags)
        file = File.join(dir, name)
        FileUtils.cp(File.join(BrowserFixture::MOCKUPS, source), file)
        run.call("mockup", file, "--question", "O1", *flags)
    end
end
