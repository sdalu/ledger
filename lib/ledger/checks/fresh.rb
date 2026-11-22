# frozen_string_literal: true

require "ledger/checks/sides"
require "ledger/stamps"

module Ledger
    module Checks
        # pictures-fresh: a picture shows the item as it was when placed,
        # so words reworded since leave it stale: a piece's plan, detail
        # or problem, an open question's detail, problem or choices; a
        # field first set after the picture is no change; a piece's
        # `--picture-holds` moves the measure to its write. A piece whose
        # picture is being redrawn (`piece --picture-pending`) is
        # announced instead on a plain check and still fails --final; the
        # write path refuses a stale piece awaiting commit, deploy, push
        # or merge unless it is being redrawn.
        module Fresh
            TIME = "%Y-%m-%d %H:%M"
            PAST = "set --picture-pending WHY, --picture-holds WHY, or " \
                   "place a new picture first"
            HINTS = {
                "pictures-fresh" =>
                    "a picture is placed after the last rewording of what " \
                    "it shows: a piece's plan, detail or problem, a " \
                    "question's detail, problem or choices; `bin/ledger " \
                    "mockup PATH " \
                    "FILE --piece P<n> --before|--after --replace`, " \
                    "`bin/ledger mockup PATH FILE --question O<n> " \
                    "--replace`, or while it is redrawn `bin/ledger piece " \
                    "PATH P<n> --picture-pending WHY`; a warning on a plain " \
                    "check, a failure on --final, and a write leaving a " \
                    "piece awaiting commit, deploy, push or merge stale " \
                    "and not being redrawn is refused"
            }.freeze

            module_function

            # Each stale item, "P81: plan, problem changed after its last
            # picture (2026-11-22 09:45)", but a piece being redrawn: what
            # a plain check warns of.
            def problems(derive)
                pieces = derive.pieces.reject { pending?(derive, it) }
                lines(derive, pieces)
            end

            # Each stale item, a piece being redrawn too: what --final
            # fails on, the redraw due before the finish.
            def final(derive) = lines(derive, derive.pieces)

            # Each piece being redrawn, "P81: picture being redrawn (WHY)".
            def notes(derive)
                derive.pieces.select { pending?(derive, it) }.map do |piece|
                    "#{derive.ref(piece)}: picture being redrawn " \
                        "(#{piece[:picture_pending]})"
                end
            end

            # Each stale piece awaiting a finishing word and not being
            # redrawn, as "P81 (awaits commit): …", with the way past:
            # what the write path compares.
            def compared(derive)
                derive.pieces.filter_map do |piece|
                    words = Sides.finishing(derive, piece)
                    next if words.empty? || pending?(derive, piece)

                    stale = piece_line(derive, piece) or next
                    "#{stale.sub(":", " (awaits #{words.join(", ")}):")} " \
                        "— #{PAST}"
                end
            end

            def lines(derive, pieces)
                questions = derive.open_questions
                pieces.filter_map { piece_line(derive, it) } +
                    questions.filter_map { question_line(derive, it) }
            end

            def pending?(derive, piece)
                derive.present?(piece[:picture_pending])
            end

            def piece_line(derive, piece)
                stamps = derive.snapshot.stamps
                placed = last(stamps, :piece_pictures, derive.pictures(piece))
                return unless placed

                placed = [placed, held(piece)].compact.max
                was = stamps.fields_at(:pieces, piece[:id], placed)
                line(derive.ref(piece), placed,
                     reworded(derive, was, piece, Stamps::FIELDS[:pieces]))
            end

            def question_line(derive, question)
                stamps = derive.snapshot.stamps
                placed = last(stamps, :question_pictures,
                              question_pictures(derive, question)) or return
                was = stamps.fields_at(:questions, question[:id], placed)
                changed = reworded(derive, was, question,
                                   Stamps::FIELDS[:questions])
                changed << "choices" if
                    choices_reworded?(derive, stamps, question, placed)
                line(derive.qref(question), placed, changed)
            end

            # The question's picture rows that name a picture.
            def question_pictures(derive, question)
                derive.snapshot.question_pictures.select do |row|
                    row[:question_id] == question[:id] && row[:name]
                end
            end

            # When the writer said the picture still holds; nil unsaid.
            def held(piece)
                piece[:picture_holds_at] if piece[:picture_holds]
            end

            # When the last of ROWS (picture rows of TABLE) was placed.
            def last(stamps, table, rows)
                rows.filter_map { stamps.placed(table, it[:id]) }.max
            end

            # The FIELDS that held words when the picture was placed (WAS)
            # and hold other words now: a field first set is no change.
            def reworded(derive, was, row, fields)
                fields.select do |field|
                    derive.present?(was[field]) &&
                        was[field] != row[field.to_sym]
                end
            end

            def choices_reworded?(derive, stamps, question, placed)
                was = stamps.choices_at(question[:id], placed)
                now = derive.snapshot.question_choices.select do |row|
                    row[:question_id] == question[:id]
                end
                now = now.map { it.values_at(:label, :effect, :cost) }
                was.any? && was != now.sort_by { it.map(&:to_s) }
            end

            def line(ref, placed, changed)
                return if changed.empty?

                "#{ref}: #{changed.join(", ")} changed after its last " \
                    "picture (#{Time.at(placed / 1000).strftime(TIME)})"
            end
        end
    end
end
