# frozen_string_literal: true

require "ledger/commands/decide"
require "ledger/commands/edit_rows"
require "ledger/commands/goal"

module Ledger
    module Commands
        # `edit PATH ID --text T`: the words of an item that has no writer
        # of its own: a fact's text, an assumption's text (its check
        # staying), a constraint's line, a decision's body, a question's
        # detail, a noticed line (Z<n>); and `edit PATH goal` the latest
        # Goal block's title (--text), In short (--short) and Context
        # (--context), its quote staying the user's words.
        class Edit < CLI::Command
            include EditRows

            USAGE = "PATH ID"
            SYNOPSIS = "PATH ID --text T | goal [--text --short --context]"
            SUMMARY = "reword a fact, assumption, constraint, decision, " \
                      "question's detail, noticed line (Z<n>) or the " \
                      "goal's title, short and context (goal)"
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
