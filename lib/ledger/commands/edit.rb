# frozen_string_literal: true

require "ledger/commands/decide"
require "ledger/commands/goal"

module Ledger
    module Commands
        # `edit PATH ID --text T`: the words of an item that has no writer
        # of its own: a fact's text, a constraint's line, a decision's
        # body, a question's detail, a noticed line (Z<n>); and `edit PATH
        # goal` the latest Goal block's title (--text), In short (--short)
        # and Context (--context), its quote staying the user's words.
        class Edit < CLI::Command
            USAGE = "PATH ID"
            SYNOPSIS = "PATH ID --text T | goal [--text --short --context]"
            SUMMARY = "reword a fact, constraint, decision, question's " \
                      "detail, noticed line (Z<n>) or the goal's title, " \
                      "short and context (goal)"
            QUOTE = /["“](.+?)["”]/
            Z = /\AZ([1-9]\d*)\z/
            COLUMN = { "O" => %i[questions detail] }.freeze
            # The item letters whose words another command writes.
            OWN_WRITER = { "P" => "piece PATH P<n> --what",
                           "D" => "criterion PATH D<n> --text" }.freeze
            UNKNOWN = "is not an item edit takes (F, C, X, O, Z, goal)"
            OPTIONS = {
                text: ["--text TEXT", "the new words"],
                short: ["--short SENTENCE", "goal: its In short"],
                context: ["--context POINTERS", "goal: its Context"],
                pointer: ["--pointer WHERE", "a fact: where it was found"]
            }.freeze

            private

            def flags(parser) = dry_run(parser)

            def run(path, id)
                return regoal(path) if id == "goal"

                own_flags!(id)
                words = words(id)
                result = write(path, own: id) do |change|
                    change_item(change, id, words)
                end
                emit(result, path, lines: [shown(result.after, id)])
                0
            end

            def own_flags!(id)
                refuse("--short and --context are the goal's") if
                    @opts.key?(:short) || @opts.key?(:context)
                refuse("--pointer is a fact's") if
                    @opts.key?(:pointer) && !id.start_with?("F")
            end

            # A fact's text and pointer, either or both; else the text.
            def words(id)
                return { text: line(@opts[:text], "--text") } unless
                    id.start_with?("F")

                given = %i[text pointer].select { @opts.key?(it) }
                refuse("a fact takes --text, --pointer or both") if
                    given.empty?
                given.to_h { [it, line(@opts[it], "--#{it}")] }
            end

            def regoal(path)
                edit = GoalEdit.new(@opts) { |text, what| line(text, what) }
                result = write(path, own: "Goal") do |change|
                    edit.apply(change, journal.db)
                end
                emit(result, path, lines: edit.lines(result.after))
                0
            end

            def change_item(change, id, words)
                text = words[:text]
                case id
                when /\AF/ then fact(change, id, words)
                when Z then noticed(change, Regexp.last_match(1).to_i, text)
                when /\AC/ then constraint(change, id, text)
                when /\AX/ then decision(change, id, text)
                else column(change, id, text)
                end
            end

            def fact(change, id, words)
                change.update(:facts, change.resolve(id).last[:id], **words)
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
                return Render::Markdown.line(snapshot, id) unless Z.match?(id)

                snapshot.noticed.find { "Z#{it[:id]}" == id }[:line]
            end
        end

        # `edit PATH goal`: the latest Goal block's title (--text), In short
        # (--short) and Context (--context), one or more in one write; the
        # quote is the user's and only `goal` appends a revision of it.
        class GoalEdit
            FIELDS = { text: [:title, "Title"], short: [:short, "In short"],
                       context: [:context, "Context"] }.freeze

            # LINE checks one value as a line: (text, what) -> text.
            def initialize(opts, &line)
                given = FIELDS.keys.select { opts.key?(it) }
                fail!("goal takes --text (its title), --short or --context") if
                    given.empty?
                @columns = given.to_h do |key|
                    column, = FIELDS.fetch(key)
                    [column, line.call(opts[key], "--#{key}")]
                end
            end

            def apply(change, db)
                row = db[:goals].where(ledger_id: change.ledger_id)
                                .order(:id).last
                fail!("no Goal block to edit") unless row
                title!
                change.update(:goals, row[:id], **@columns)
            end

            # What the write prints: each field changed, as the Goal block
            # shows it.
            def lines(snapshot)
                goal = snapshot.goals.last
                FIELDS.values.filter_map do |column, label|
                    "#{label}: #{goal[column]}" if @columns.key?(column)
                end
            end

            private

            def title!
                return unless @columns.key?(:title)

                @columns[:title] = Goal.flat(@columns[:title])
                problem = Text::Title.problem(@columns[:title])
                fail!(problem) if problem
            end

            def fail!(message) = raise(Refused, message)
        end
    end
end
