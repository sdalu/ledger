# frozen_string_literal: true

require "ledger/render/assumption_line"
require "ledger/render/items"
require "ledger/render/piece_line"
require "ledger/render/question_line"
require "ledger/render/refs"

module Ledger
    module Render
        # A Snapshot as today's LEDGER Markdown (format 2), the text
        # `show` prints, normalised as the round-trip note names (R1-R10):
        # one blank line between blocks, none inside, one final newline.
        #
        #     Ledger::Render::Markdown.render(snapshot)      # the file
        #     Ledger::Render::Markdown.line(snapshot, "P3")  # one line
        class Markdown
            HEADER = "# Ledger (format 2)"
            REF = /\A(?<kind>[PODCFXA])(?<n>[1-9]\d*)\z/
            # The table and the line builder of the kinds Items renders.
            ITEMS = { "D" => %i[criteria criterion],
                      "C" => %i[constraints constraint],
                      "F" => %i[facts fact],
                      "X" => %i[decisions decision] }.freeze
            # The sections of Items' kinds, in file order, by label.
            SECTIONS = { "Done when" => "D",
                         "Constraints (verbatim, where said)" => "C",
                         "Facts" => "F", "Assumptions" => "A",
                         "Decisions" => "X" }.freeze

            def self.render(snapshot) = new(snapshot).render

            # The line of the item REF names (P, O, D, C, F, A or X).
            def self.line(snapshot, ref) = new(snapshot).line(ref)

            def initialize(snapshot)
                @snapshot = snapshot
                refs = Refs.new(snapshot)
                @piece = PieceLine.new(snapshot, refs)
                @question = QuestionLine.new(snapshot, refs)
                @assumption = AssumptionLine.new(snapshot, refs)
            end

            def render
                "#{[HEADER, *blocks.map { it.join("\n") }].join("\n\n")}\n"
            end

            def line(ref)
                match = REF.match(ref.to_s)
                raise Unknown, "#{ref} is not an id" unless match

                kind = match[:kind]
                row = rows(kind).find { it[:n] == match[:n].to_i }
                raise Unknown, "#{ref} is not this ledger's" unless row

                render_row(kind, row)
            end

            private

            def blocks
                [*goals, *SECTIONS.map { |label, kind| section(label, kind) },
                 labelled("Pieces", @snapshot.pieces.map { @piece.call(it) }),
                 labelled("Open", open_questions.map { @question.call(it) }),
                 labelled("Out of scope, noticed",
                          @snapshot.noticed.map { it[:line] })]
            end

            def goals
                @snapshot.goals.map do |row|
                    [Items.goal_label(row), *Items.goal(row)]
                end
            end

            def labelled(label, lines) = ["#{label}:", *lines]

            def section(label, kind)
                if kind == "A"
                    return labelled(label, @snapshot.assumptions.map do |row|
                        assumption(row)
                    end)
                end

                table, builder = ITEMS.fetch(kind)
                labelled(label, @snapshot[table].map do |row|
                    Items.public_send(builder, row)
                end)
            end

            def open_questions
                @snapshot.questions.select { it[:closed_at].nil? }
            end

            def rows(kind)
                return @snapshot.pieces if kind == "P"
                return @snapshot.questions if kind == "O"
                return @snapshot.assumptions if kind == "A"

                @snapshot[ITEMS.fetch(kind).first]
            end

            def render_row(kind, row)
                return @piece.call(row) if kind == "P"
                return @question.call(row) if kind == "O"
                return assumption(row) if kind == "A"

                Items.public_send(ITEMS.fetch(kind).last, row)
            end

            def assumption(row) = @assumption.call(row)
        end
    end
end
