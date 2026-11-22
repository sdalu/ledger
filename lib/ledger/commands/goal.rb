# frozen_string_literal: true

require "ledger/commands/heard"
require "ledger/text/title"

module Ledger
    module Commands
        # `goal PATH --quote --title --short [--context] [--date]`: a
        # revised Goal block, the user's new words verbatim under the
        # session's Title, In short and Context, its id the next G<n>;
        # `goal PATH G<n> --done EVIDENCE | --undone`: the block marked
        # done, or active again. A quote not in a message of the user's
        # is warned of unless --said-in says where it was said (Heard).
        class Goal < CLI::Command
            include Heard

            USAGE = "PATH [ID]"
            SYNOPSIS = "PATH --quote W --title T --short S | " \
                       "PATH G<n> --done E|--undone"
            SUMMARY = "append a revised Goal block, the user's new words " \
                      "verbatim; or mark a Goal block done or active"
            OPTIONS = {
                quote: ["--quote WORDS", "the user's new words, verbatim"],
                title: ["--title TITLE", "a short name, at most 60 characters"],
                short: ["--short SENTENCE",
                        "the goal in one sentence, your own words"],
                context: ["--context POINTERS",
                          "the files and places it concerns"],
                date: ["--date DATE", DATE],
                done: ["--done EVIDENCE",
                       "G<n>: mark it done, with the evidence"],
                said_in: Heard::SAID_IN
            }.freeze
            DATE = /\A\d{4}-\d{2}-\d{2}\z/

            # The goals row the options OPTS describe, refused when its
            # title, short line, date or quote are wrong; shared with `new`.
            def self.row(opts, revised:)
                date = opts.fetch(:date) { Time.now.strftime("%F") }
                raise Refused, "--date is YYYY-MM-DD" unless DATE.match?(date)

                label = revised ? "revised, verbatim" : "verbatim"
                { stamp: "#{date}, #{label}", date:, revised:,
                  **words(opts), quote: quote(given(opts, :quote)),
                  said_in: said_in(opts[:said_in]) }
            end

            # --said-in's WHERE on one line; nil when not given.
            def self.said_in(text)
                return if text.nil?
                raise Refused, "--said-in is empty" if text.strip.empty?

                flat(text)
            end

            def self.given(opts, name)
                opts.fetch(name) { raise Refused, "--#{name} is required" }
            end

            def self.words(opts)
                title = given(opts, :title)
                short = given(opts, :short)
                problem = Text::Title.problem(title)
                raise Refused, problem if problem
                raise Refused, "--short is empty" if short.strip.empty?

                { title: flat(title), short: flat(short),
                  context: context(opts[:context]) }
            end

            def self.context(text)
                flat(text) unless text.to_s.strip.empty?
            end

            def self.quote(text)
                raise Refused, "the quote is empty" if text.strip.empty?

                text.strip.split(/\r?\n/, -1).join("\n")
            end

            def self.flat(text) = text.split.join(" ")

            # The block's lines as a write prints them.
            def self.block(row)
                [Render::Items.goal_label(row), *Render::Items.goal(row)]
            end

            private

            def flags(parser)
                parser.on("--undone", "G<n>: mark it active again") do
                    @opts[:undone] = true
                end
                dry_run(parser)
            end

            def run(path, id = nil)
                return mark(path, id) if id

                refuse("--done and --undone name a goal: goal PATH G<n>") if
                    @opts.key?(:done) || @opts.key?(:undone)
                append(path)
            end

            def append(path)
                row = self.class.row(@opts, revised: true)
                refuse(Checks::Goal::GO_AHEAD) if
                    row[:quote].split.size < Checks::Goal::REVISION_WORDS
                result = write(path, own: "#{row[:date]}, revised") do |change|
                    change.insert(:goals, n: change.next_id("G"), **row)
                end
                report(result, path, row)
            end

            # The block written, then the quote's warning if any.
            def report(result, path, row)
                emit(result, path,
                     lines: self.class.block(result.after.goals.last))
                quoted!(row[:quote])
                0
            end

            def mark(path, id)
                marker = GoalMark.new(id, @opts)
                result = write(path, own: id) { marker.apply(it) }
                emit(result, path, lines: self.class.block(result.value))
                0
            end
        end

        # `goal PATH G<n> --done EVIDENCE | --undone`: a Goal block's done
        # mark, its time and evidence set together and cleared together.
        class GoalMark
            ID = /\AG[1-9]\d*\z/
            BLOCK = %i[quote title short context date said_in].freeze

            def initialize(id, opts)
                fail!("the target is G<n>, a Goal block's id") unless
                    ID.match?(id)
                @id = id
                @done = opts[:done]
                @undone = opts[:undone]
                alone!(opts)
            end

            # The block's row once marked.
            def apply(change)
                row = block(change)
                change.update(:goals, row[:id], **columns(change, row))
                change.resolve(@id).last
            end

            private

            # --done or --undone, one of them, nothing else of the block.
            def alone!(opts)
                fail!("give one of --done EVIDENCE, --undone") unless
                    [@done, @undone].one?
                if opts.keys.intersect?(BLOCK)
                    fail!("--done and --undone go without --quote, --title, " \
                          "--short, --context, --date or --said-in")
                end
                fail!("--done takes the evidence; it is empty") if
                    @done && @done.strip.empty?
            end

            def block(change)
                change.resolve(@id).last
            rescue Unknown
                fail!("#{@id} is not a Goal block of this ledger")
            end

            def columns(change, row)
                done = !row[:done_at].nil?
                if @done
                    fail!("#{@id} is done already") if done
                    return { done_at: change.at,
                             done_evidence: Goal.flat(@done) }
                end
                fail!("#{@id} is not done") unless done
                { done_at: nil, done_evidence: nil }
            end

            def fail!(message) = raise(Refused, message)
        end
    end
end
