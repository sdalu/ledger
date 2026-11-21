# frozen_string_literal: true

require "ledger/text/codes"
require "ledger/text/options"
require "ledger/text/pointer"

module Ledger
    module Checks
        # codes: an id-shaped code that is not one of this ledger's kinds
        # (W1 from another note) is named in words or pointed to. A
        # question points to it with `— see:` an item whose words name
        # it; words around the code are not a pointer. The Goal quote and
        # the constraint quotes are the user's words and not read.
        module Codes
            # The text of each kind of item, as the columns that hold it.
            PIECE = %i[title detail problem plan].freeze
            QUESTION = %i[title detail problem risk recommend].freeze
            GOAL = %i[title short context].freeze
            FACT = %i[text pointer].freeze
            STANDING = [[:decisions, "X", %i[body note]], [:facts, "F", FACT],
                        [:noticed, "Z", %i[line]]].freeze
            SEEN = { constraint_id: [:constraints, %i[text]],
                     criterion_id: [:criteria, %i[text]],
                     fact_id: [:facts, FACT],
                     piece_id: [:pieces, %i[title detail]] }.freeze

            module_function

            # "P3: W1, S4" for each item holding codes, in page order.
            def problems(derive)
                (goal(derive) + pieces(derive) + questions(derive) +
                 standing(derive)).filter_map do |id, codes|
                    "#{id}: #{codes.join(", ")}" if codes.any?
                end
            end

            def goal(derive)
                block = derive.snapshot.goals.last or return []
                [["Goal (#{block[:stamp]})", codes(block, GOAL)]]
            end

            def pieces(derive)
                derive.pieces.select { derive.in_flight?(it) }
                      .map { [derive.ref(it), codes(it, PIECE)] }
            end

            # An open question's codes but its own items' and options'
            # labels (`— items: S1 | S2`, which the picker grammar names)
            # and those a see: item names.
            def questions(derive)
                derive.open_questions.map do |question|
                    own = labels(derive, question)
                    seen = seen_text(derive.snapshot, question)
                    [derive.qref(question),
                     codes(question, QUESTION).reject do |code|
                         own.include?(code) ||
                             seen.any? { Text::Codes.names?(it, code) }
                     end]
                end
            end

            def labels(derive, question)
                (derive.items(question) + derive.options(question))
                    .map { Text::Options.code(it) }
            end

            # Decisions, facts, constraints' where, noticed lines.
            def standing(derive)
                snap = derive.snapshot
                where = snap.constraints.map do |row|
                    ["C#{row[:n]}", where_codes(row)]
                end
                rest = STANDING.flat_map do |table, kind, columns|
                    snap[table].map { [id(kind, it), codes(it, columns)] }
                end
                where + rest
            end

            # A noticed line's id is its row's.
            def id(kind, row) = "#{kind}#{kind == "Z" ? row[:id] : row[:n]}"

            def where_codes(row)
                Text::Codes.find(Text::Pointer.where(row[:text], row[:quote]))
            end

            def codes(row, columns)
                columns.flat_map { Text::Codes.find(row[it]) }.uniq
            end

            # The words of the items QUESTION's see: names.
            def seen_text(snapshot, question)
                sees = snapshot.question_sees.select do |see|
                    see[:question_id] == question[:id]
                end
                sees.flat_map { target_text(snapshot, it) }
            end

            def target_text(snapshot, see)
                column, (table, fields) = SEEN.find { |col, _| see[col] }
                row = snapshot[table].find { it[:id] == see[column] }
                row ? row.values_at(*fields).compact : []
            end
        end
    end
end
