# frozen_string_literal: true

require "ledger/text/options"
require "ledger/text/picker"
require "ledger/text/risk"
require "ledger/text/title"

module Ledger
    module Commands
        # What `ask` and `choice` print of a question on a dry run: its
        # picker as the card offers it.
        module Card
            private

            def card(snapshot, ref)
                derive = Derive.read(journal.db, snapshot)
                question = derive.open_questions.find { "O#{it[:n]}" == ref }
                Text::Card.lines(ref, derive.options(question),
                                 derive.items(question),
                                 question[:recommend].to_s,
                                 Checks::Open.picker_problems(derive, question))
            end
        end

        # `ask PATH QUESTION --title [--choices --by --items --see --problem
        # --risk --recommend] (--mockup NAME | --pending P<n> | --no-picture
        # WHY) [--replaces O<n>]`: a question under Open; `--replaces`
        # closes an open one in the same write, files the decision and
        # writes the O->O replaces edge.
        class Ask < CLI::Command
            include Card

            USAGE = "PATH QUESTION"
            FLAGS = %w[title choices by items see problem risk recommend
                       mockup pending replaces].freeze
            PICTURE = "say what picture the question has, one of --mockup " \
                      "NAME (a picture already in the journal), --pending " \
                      "P<n> (a piece draws it), --no-picture 'why' (it " \
                      "needs none)"

            private

            def flags(parser)
                FLAGS.each do |name|
                    parser.on("--#{name} VALUE") { @opts[name] = it }
                end
                # Spelled "--no-picture WHY", OptionParser would read the
                # negation of a --picture switch and leave WHY behind.
                parser.on("--no-picture", "=WHY", String) do |why|
                    @opts["no-picture"] = why
                end
                dry_run(parser)
            end

            def run(path, question)
                opts = check(question)
                result = write(path) do |change|
                    AskWriter.new(change, journal.db, @opts, path)
                             .call(question.strip, opts)
                end
                report(result, path, opts)
                0
            end

            # The options, once every rule that needs no journal passed.
            def check(question)
                titled(need("title"), question)
                why = Text::Risk.case_problem(@opts["problem"].to_s,
                                              @opts["risk"].to_s)
                refuse("a question gives #{why}") if why
                refuse("the question is empty") if question.strip.empty?
                picture
                options
            end

            def titled(title, question)
                why = Text::Title.problem(title) ||
                      Text::Title.detail_problem(question)
                refuse(why) if why
            end

            def picture
                given = %w[mockup pending no-picture].select { @opts.key?(it) }
                refuse(PICTURE) unless given.one?
                if given == ["no-picture"] &&
                   @opts["no-picture"].strip.empty?
                    refuse("--no-picture says why the question needs no " \
                           "picture")
                end
            end

            def options
                opts = Text::Options.split(@opts["choices"].to_s)
                (why = Text::Options.problem(opts)) and refuse(why)
                if @opts["items"] && opts.empty?
                    refuse("--items needs --choices, the answers offered per " \
                           "item")
                end
                opts
            end

            def report(result, path, opts)
                ref = result.value
                lines = [Render::Markdown.line(result.after, ref)]
                lines += card(result.after, ref) if result.dry
                emit(result, path, first: ref, lines:)
                return unless opts.size.between?(Text::Picker::OPTIONS_WARN,
                                                 Text::Picker::OPTIONS_MAX)

                @err.puts "ask: warning: #{opts.size} options; seven or " \
                          "eight is a lot to weigh"
            end
        end

        # The rows of one `ask`: the question, its choices, items, sees
        # and picture, and what `--replaces` closes and files.
        class AskWriter
            SEES = { "C" => :constraint_id, "D" => :criterion_id,
                     "F" => :fact_id, "P" => :piece_id }.freeze

            def initialize(change, db, opts, path)
                @change = change
                @db = db
                @opts = opts
                @address = Address.parse(path)
            end

            # -> the new question's id.
            def call(detail, opts)
                picture = AskPicture.new(@change, @db, @opts).row
                children = [picture, sees, by]
                replacing = Replacing.new(@change, @db, @opts, @address)
                old = replacing.question
                n = @change.next_id("O")
                @change.own = "O#{n}"
                id = @change.insert(:questions, n:, detail:, **columns, **by_id)
                rows(id, opts, children)
                replacing.call(old, n) if old
                @change.own
            end

            private

            def refuse(message) = raise(Refused, message)
            def by_id = { by_id: @by }

            def columns
                risk = @opts["risk"]&.strip
                { title: @opts["title"].strip, problem: @opts["problem"]&.strip,
                  risk:, risk_rating: risk && Text::Risk.rating(risk).first,
                  recommend: @opts["recommend"]&.strip,
                  no_picture: @opts["no-picture"]&.strip }
            end

            def rows(id, opts, (picture, sees, _))
                choices(id, opts)
                items(id)
                sees.each_with_index do |see, position|
                    see_row(id, see, position)
                end
                insert_picture(id, picture)
            end

            def choices(id, opts)
                opts.each_with_index do |option, position|
                    label, effect, cost = Text::Options.parts(option)
                    @change.insert(:question_choices, question_id: id,
                                                      position:, label:,
                                                      effect: blank(effect),
                                                      cost: blank(cost))
                end
            end

            def blank(text) = (text unless text.empty?)

            def items(id)
                Text::Options.split(@opts["items"].to_s)
                             .each_with_index do |text, position|
                    @change.insert(:question_items, question_id: id,
                                                    position:, text:)
                end
            end

            def see_row(id, (column, row), position)
                @change.insert(:question_sees, question_id: id, position:,
                                               column => row)
            end

            def insert_picture(id, picture)
                return unless picture

                @change.insert(:question_pictures, question_id: id,
                                                   position: 0, **picture)
            end

            # [[column, row id]] of the items `--see` names.
            def sees
                ids(@opts["see"]).map do |ref|
                    column = SEES[ref[0]] or
                        refuse("--see takes C/D/F/P ids, not #{ref}")
                    [column, @change.resolve(ref).last[:id]]
                end
            end

            def ids(value) = value.to_s.split(/[,\s]+/).reject(&:empty?)

            def by
                ref = @opts["by"]&.strip or return
                refuse("--by names a piece, P<n>") unless
                    ref.match?(/\AP[1-9]\d*\z/)
                row = @change.resolve(ref).last
                if row[:status] == "dropped"
                    refuse("--by #{ref}: that piece is dropped and will " \
                           "prepare nothing")
                end
                @by = row[:id]
            end
        end

        # The picture decision of an `ask`: a name placed in the
        # journal, or a pending piece that will draw it.
        class AskPicture
            def initialize(change, db, opts)
                @change = change
                @db = db
                @opts = opts
            end

            # The picture row: a name in the journal, or a pending piece;
            # nil for --no-picture.
            def row
                return pending(@opts["pending"].strip) if @opts["pending"]
                return unless @opts["mockup"]

                name = @opts["mockup"].strip
                unless placed?(name)
                    refuse("--mockup #{name}: no picture of that name in the " \
                           "journal; place it first, or --pending P<n> / " \
                           "--no-picture 'why'")
                end
                { name: }
            end

            private

            def refuse(message) = raise(Refused, message)

            def placed?(name)
                @db[:pictures].where(ledger_id: @change.ledger_id, name:).any?
            end

            def pending(ref)
                refuse("--pending names a piece, P<n>") unless
                    ref.match?(/\AP[1-9]\d*\z/)
                row = piece(ref) or
                    refuse("--pending #{ref}: no such piece; add it first, " \
                           "`ledger piece PATH new …`")
                if row[:status] == "dropped"
                    refuse("--pending #{ref}: that piece is dropped and will " \
                           "draw nothing")
                end
                { pending_id: row[:id] }
            end

            def piece(ref)
                @db[:pieces].where(ledger_id: @change.ledger_id,
                                   n: ref[1..].to_i).first
            end
        end

        # What `ask --replaces O<n>` does besides the new question: the
        # open question it names, refused while the viewer holds an entry
        # about it, closed with the decision by me and the O->O edge.
        class Replacing
            def initialize(change, db, opts, address)
                @change = change
                @db = db
                @opts = opts
                @address = address
            end

            # The open question `--replaces` names, once nothing the viewer
            # holds about it waits to be taken; nil without the flag.
            def question
                ref = @opts["replaces"]&.strip or return
                row = open_question(ref) or
                    refuse("--replaces #{ref}: not asked under Open in " \
                           "#{@address}")
                held = untaken(ref)
                return row if held.empty?

                refuse("--replaces #{ref}: the viewer holds " \
                       "#{held.join(", ")} about it, not taken yet; file it " \
                       "first (`ledger answer PATH #{ref} … --take " \
                       "#{held.first}`)")
            end

            # Close OLD, file the decision by me with its X answers OLD,
            # write O<n> replaces OLD.
            def call(old, n)
                @change.update(:questions, old[:id], closed_at: Write.now)
                body = "O#{old[:n]}: replaced by O#{n} " \
                       "(#{@opts["title"].strip})"
                x = @change.next_id("X")
                @change.insert(:decisions, n: x, date: Time.now.strftime("%F"),
                                           body:, by: "me",
                                           subject: "O#{old[:n]}")
                @change.link("answers", "X#{x}", "O#{old[:n]}")
                @change.link("replaces", "O#{n}", "O#{old[:n]}")
            end

            private

            def refuse(message) = raise(Refused, message)

            def open_question(ref)
                return unless ref.match?(/\AO[1-9]\d*\z/)

                @db[:questions].where(ledger_id: @change.ledger_id,
                                      n: ref[1..].to_i, closed_at: nil).first
            end

            def untaken(ref)
                @db[:inbox_entries].where(ledger_id: @change.ledger_id, ref:,
                                          taken_id: nil)
                                   .order(:id).select_map(:n).map { "N#{it}" }
            end
        end
    end
end
