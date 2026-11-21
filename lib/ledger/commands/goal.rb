# frozen_string_literal: true

require "ledger/text/title"

module Ledger
    module Commands
        # `goal PATH --quote --title --short [--context] [--date]`: a
        # revised Goal block, the user's new words verbatim under the
        # session's Title, In short and Context.
        class Goal < CLI::Command
            USAGE = "PATH"
            DATE = /\A\d{4}-\d{2}-\d{2}\z/

            # The goals row the options OPTS describe, refused when its
            # title, short line, date or quote are wrong; shared with `new`.
            def self.row(opts, revised:)
                date = opts.fetch(:date) { Time.now.strftime("%F") }
                raise Refused, "--date is YYYY-MM-DD" unless DATE.match?(date)

                label = revised ? "revised, verbatim" : "verbatim"
                { stamp: "#{date}, #{label}", date:, revised:,
                  **words(opts), quote: quote(given(opts, :quote)) }
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

            private

            def flags(parser)
                parser.on("--quote WORDS") { @opts[:quote] = it }
                parser.on("--title TITLE") { @opts[:title] = it }
                parser.on("--short SENTENCE") { @opts[:short] = it }
                parser.on("--context POINTERS") { @opts[:context] = it }
                parser.on("--date DATE") { @opts[:date] = it }
                dry_run(parser)
            end

            def run(path)
                row = self.class.row(@opts, revised: true)
                refuse(Checks::Goal::GO_AHEAD) if
                    row[:quote].split.size < Checks::Goal::REVISION_WORDS
                result = write(path, own: "#{row[:date]}, revised") do |change|
                    change.insert(:goals, **row)
                end
                emit(result, path, lines: block(result.after.goals.last))
                0
            end

            def block(row)
                [Render::Items.goal_label(row), *Render::Items.goal(row)]
            end
        end
    end
end
