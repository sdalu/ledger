# frozen_string_literal: true

require "ledger/commands/ask"
require "ledger/text/options"

module Ledger
    module Commands
        # `choice PATH O<n> (--add "LABEL = effect; cost" | --drop LABEL)`:
        # add an option to an open question's choices, or drop one; the
        # options keep the grammar `ask` keeps, and the question passes
        # open-picker afterwards (the write path's checks, O<n> its own).
        class Choice < CLI::Command
            include Card

            USAGE = "PATH ID"
            ID = /\AO[1-9]\d*\z/

            private

            def flags(parser)
                parser.on("--add OPTION") { @opts[:add] = it }
                parser.on("--drop LABEL") { @opts[:drop] = it }
                dry_run(parser)
            end

            def run(path, id)
                refuse("the target is O<n>") unless ID.match?(id)
                refuse("give one of --add, --drop") unless
                    @opts.values_at(:add, :drop).compact.one?
                result = write(path, own: id) do |change|
                    edit(change, question(change, id, path))
                end
                lines = [Render::Markdown.line(result.after, id)]
                lines += card(result.after, id) if result.dry
                emit(result, path, lines:)
                0
            end

            def question(change, id, path)
                row = journal.db[:questions].where(ledger_id: change.ledger_id,
                                                   n: id[1..].to_i,
                                                   closed_at: nil).first
                return row if row

                refuse("#{id} is not asked under Open in " \
                       "#{Address.parse(path)}")
            end

            def edit(change, question)
                rows = journal.db[:question_choices]
                              .where(question_id: question[:id])
                              .order(:position, :id).all
                if rows.empty?
                    refuse("O#{question[:n]} has no `choices:`; ask it with " \
                           "--choices")
                end
                opts = rows.map { option(it) }
                return add(change, question, rows) if @opts[:add]

                drop(change, rows, opts)
            end

            def option(row)
                label, effect, cost = row.values_at(:label, :effect, :cost)
                text = label
                text += " = #{effect}" unless effect.to_s.empty?
                text += "; #{cost}" unless cost.to_s.empty?
                text
            end

            def add(change, question, rows)
                _, why = Text::Options.add(rows.map { option(it) }, @opts[:add])
                refuse(why) if why
                label, effect, cost = Text::Options.parts(@opts[:add].strip)
                change.insert(:question_choices,
                              question_id: question[:id],
                              position: rows.last[:position] + 1, label:,
                              effect: (effect unless effect.empty?),
                              cost: (cost unless cost.empty?))
            end

            def drop(change, rows, opts)
                _, why = Text::Options.drop(opts, @opts[:drop])
                refuse(why) if why
                fold = Text::Options.fold(@opts[:drop])
                rows.select { Text::Options.fold(it[:label]) == fold }
                    .each { change.delete(:question_choices, it[:id]) }
            end
        end
    end
end
