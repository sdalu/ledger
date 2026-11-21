# frozen_string_literal: true

require_relative "ledger_commands"

# The ledger test/browser/viewer.cjs expects, made by bin/ledger's
# words in the caller's journal: the goal, D1, F1, the pieces P1 to P4,
# the questions O1 to O3 with O1's two pictures (mockups/ beside this
# file), and the inbox the viewer sent, N1 about O3 waiting and N2
# taken.
module BrowserFixture
    MOCKUPS = File.join(__dir__, "browser_fixture", "mockups")
    GOAL = ["--goal", "fix the calendar, the noise $\\sigma^2$ **bounded**",
            "--title", "Port the parser", "--short", "port the parser to C23",
            "--date", "2026-11-19"].freeze
    FACT = "leftovers, not re-checked: V1 radii (menu.css:28); V2 one " \
           "shadow (room.css:211); S1 empty slot — doc/r.md:3"
    PIECES = [
        ["--route", "sonnet, effort: medium",
         "--title", "document the priority range", "--for", "D1"],
        ["--route", "peer: Other", "--title", "draw the header options",
         "--status", "out", "--session", "Other"],
        ["--route", "haiku, effort: low", "--title", "update the changelog",
         "--after", "P1"],
        ["--route", "sonnet, effort: low", "--title", "fix the reorder",
         "--problem", "the reorder fix is ready, not committed",
         "--risk", "2/10 — the fix waits; nothing breaks",
         "--plan", "commit it, then deploy the build",
         "--awaits", "commit, deploy", "--status", "verified",
         "--verified-by", "me",
         "--evidence", "suite green, see [P99](#piece-P99)"]
    ].freeze
    QUESTIONS = [
        ["what range does an entry take?",
         "--title", "Calendar entry priority",
         "--problem", "the API accepts any priority, the doc says 1-16",
         "--risk", "5/10 — a client sending 40 is ranked last",
         "--choices", "A = document 1-16 (one line) | B = cap at 16 " \
                      "(~4 files: route, tests), the file named in your " \
                      "comment",
         "--recommend", "A, nothing sends above 16", "--see", "F1",
         "--pending", "P1"],
        ["take each?", "--title", "Header items",
         "--problem", "the header is crowded",
         "--risk", "5/10 — a busy header", "--items", "S1 | S2",
         "--choices", "A = as drawn | drop = remove it",
         "--recommend", "A, it reads best", "--by", "P2",
         "--no-picture", "a choice of words"],
        ["Ship now or with the release?", "--title", "Release timing",
         "--problem", "the fix is ready", "--risk", "5/10 — early readers",
         "--choices", "C = now | D = with the release",
         "--recommend", "C, it only documents",
         "--no-picture", "a choice of words"]
    ].freeze
    SENT = [{ "ref" => "O3", "choice" => "C = now", "text" => "go" },
            { "ref" => nil, "text" => "- one\n- two" }].freeze

    # The ledger at ADDRESS in JOURNAL, one transaction: all of it or
    # nothing.
    def self.build(journal, address)
        run = lambda do |word, *args|
            LedgerCommands.run(journal, word, address, *args)
        end
        journal.transaction do
            items(run)
            pictures(run)
            Ledger::Inbox.append(journal, address, SENT,
                                 actor: "viewer:fixture")
            run.call("take", "N2")
        end
    end

    def self.items(run)
        run.call("new", *GOAL)
        run.call("fact", FACT)
        PIECES.each { run.call("piece", "new", *it) }
        QUESTIONS.each { run.call("ask", *it) }
    end

    # O1's pictures: page.html in P1's pending place, then flow.txt.
    def self.pictures(run)
        %w[page.html flow.txt].each do |name|
            run.call("mockup", File.join(MOCKUPS, name), "--question", "O1")
        end
    end
end
