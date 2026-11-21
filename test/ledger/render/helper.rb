# frozen_string_literal: true

require_relative "../helper"
require "ledger/render/markdown"

# A journal test whose rows are written through Write.run and read back
# as a Snapshot, the input the renderer takes.
class RenderTest < JournalTest
    GOAL = { stamp: "2026-11-19, verbatim", date: "2026-11-19",
             revised: false, quote: "the user's words" }.freeze

    # Runs the block as one write and answers the ledger's Snapshot.
    def snapshot(&)
        write("import", [], &).after
    end

    def render(snap) = Ledger::Render::Markdown.render(snap)

    def line(snap, ref) = Ledger::Render::Markdown.line(snap, ref)

    # The whole-ledger text of one write.
    def text(&) = render(snapshot(&))

    def goal(change, **columns)
        change.insert(:goals, n: change.next_id("G"), **GOAL, **columns)
    end

    def criterion(change, **columns)
        change.insert(:criteria, n: change.next_id("D"), mark: " ",
                                 text: "a check", **columns)
    end

    def question(change, **columns)
        n = change.next_id("O")
        change.insert(:questions, n:, title: "Title #{n}",
                                  detail: "What now?", **columns)
    end

    # The rendered line of the piece a block inserts.
    def piece_text(**columns)
        snap = snapshot { |change| piece(change, **columns) }
        line(snap, "P1")
    end

    # The rendered line of the question a block inserts.
    def question_text(**columns)
        snap = snapshot { |change| question(change, **columns) }
        line(snap, "O1")
    end
end
