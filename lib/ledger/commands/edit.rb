# frozen_string_literal: true

require "ledger/commands/decide"
require "ledger/commands/goal"

module Ledger
    module Commands
        # `edit PATH ID --text T`: the words of an item that has no writer
        # of its own: a fact's text, a constraint's line, a decision's
        # body, a question's detail, a noticed line (Z<n>) or the latest
        # Goal block's title (`goal`).
        class Edit < CLI::Command
            USAGE = "PATH ID"
            QUOTE = /["“](.+?)["”]/
            Z = /\AZ([1-9]\d*)\z/
            COLUMN = { "F" => %i[facts text],
                       "O" => %i[questions detail] }.freeze
            # The item letters whose words another command writes.
            OWN_WRITER = { "P" => "piece PATH P<n> --what",
                           "D" => "criterion PATH D<n> --text" }.freeze
            UNKNOWN = "is not an item edit takes (F, C, X, O, Z, goal)"

            private

            def flags(parser)
                parser.on("--text TEXT") { @opts[:text] = it }
                dry_run(parser)
            end

            def run(path, id)
                text = line(@opts[:text], "--text")
                result = write(path,
                               own: id == "goal" ? "Goal" : id) do |change|
                    change_item(change, id, text)
                end
                emit(result, path, lines: [shown(result.after, id)])
                0
            end

            def change_item(change, id, text)
                case id
                when "goal" then retitle(change, text)
                when Z then noticed(change, Regexp.last_match(1).to_i, text)
                when /\AC/ then constraint(change, id, text)
                when /\AX/ then decision(change, id, text)
                else column(change, id, text)
                end
            end

            def retitle(change, text)
                row = journal.db[:goals].where(ledger_id: change.ledger_id)
                             .order(:id).last
                refuse("no Goal block to edit") unless row
                title = Goal.flat(text)
                problem = Text::Title.problem(title)
                refuse(problem) if problem
                change.update(:goals, row[:id], title:)
            end

            def noticed(change, id, text)
                row = journal.db[:noticed].where(ledger_id: change.ledger_id,
                                                 id:).first
                refuse("Z#{id} is not this ledger's") unless row
                change.update(:noticed, id, line: "- #{text}")
            end

            def constraint(change, id, text)
                quote = text[QUOTE, 1] || text.split(" — ").first
                change.update(:constraints, change.resolve(id).last[:id],
                              text:, quote:)
            end

            def decision(change, id, text)
                row = change.resolve(id).last
                shape = "- #{row[:date]} — #{text} — by #{row[:by]}"
                shape += " (#{row[:note]})" if row[:note]
                refuse("not a decision line: #{shape}") unless
                    Decide::LINE.match?(shape)
                subject = text[Decide::SUBJECT, 1]
                change.update(:decisions, row[:id], body: text, subject:)
            end

            def column(change, id, text)
                table, name = COLUMN.fetch(id[0]) { unedited(id) }
                change.update(table, change.resolve(id).last[:id], name => text)
            end

            def unedited(id)
                writer = OWN_WRITER[id[0]]
                refuse("#{id} has its own writer: #{writer}") if writer
                refuse("#{id} #{UNKNOWN}")
            end

            def shown(snapshot, id)
                return "Title: #{snapshot.goals.last[:title]}" if id == "goal"
                return Render::Markdown.line(snapshot, id) unless Z.match?(id)

                snapshot.noticed.find { "Z#{it[:id]}" == id }[:line]
            end
        end
    end
end
