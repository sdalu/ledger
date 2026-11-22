# frozen_string_literal: true

require "ledger/pictures"
require "ledger/text/options"

module Ledger
    module Commands
        # `mockup --question O<n> --choice LABEL`: one picture placed as
        # that option's own, drawn in its tile; the option keeps one, and
        # `--replace` swaps it.
        module MockupChoice
            private

            def choice_flags(parser)
                parser.on("--choice LABEL", "the option of the question " \
                                            "the picture is for") do |label|
                    @opts[:choice] = label.strip
                end
            end

            def choice_mockup(path, sources)
                question = question_id
                refuse("--name does not go with --choice") if
                    @opts.key?(:name)
                items = Pictures::Sources.new(sources).items
                result = write(path, own: question) do |change|
                    place_choice(change, question, items, Address.parse(path))
                end
                report(result, question, Address.parse(path), items)
                0
            end

            # -> [[name, the file it opens on]] of the one name placed.
            def place_choice(change, question, items, address)
                row = open_question(change, question) or
                    refuse("#{question} is not asked under Open in #{address}")
                shown = one_picture(items)
                choice = choice_row(row, question)
                attach(change, choice, items, shown.first.first)
                change.summary = "placed #{shown.first.first} for " \
                                 "#{question} option #{choice[:label]}"
                shown
            end

            def one_picture(items)
                shown = Pictures.shown(items)
                return shown if shown.one?

                refuse("--choice places one picture, not #{shown.size}")
            end

            def attach(change, choice, items, name)
                Pictures::Choices.new(change, journal.db)
                                 .call(choice, items, name,
                                       replace: @opts.fetch(:replace, false))
            end

            # The option --choice names, its label folded as `choice
            # --drop` folds it; refused with the labels the question has.
            def choice_row(row, question)
                by_item!(row, question)
                rows = choices_of(row, question)
                fold = Text::Options.fold(@opts[:choice])
                rows.find { Text::Options.fold(it[:label]) == fold } or
                    refuse("#{question} has no option #{@opts[:choice]}; " \
                           "its labels: #{rows.map { it[:label] }.join(", ")}")
            end

            # Options answered per item are plain buttons: no tile to
            # draw a picture in.
            def by_item!(row, question)
                return unless journal.db[:question_items]
                                     .where(question_id: row[:id]).any?

                refuse("#{question} is answered item by item; its options " \
                       "carry no picture of their own: place one picture " \
                       "for the question")
            end

            def choices_of(row, question)
                rows = journal.db[:question_choices]
                              .where(question_id: row[:id])
                              .order(:position, :id).all
                return rows if rows.any?

                refuse("#{question} has no `choices:`")
            end
        end
    end
end
