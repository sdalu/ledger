# frozen_string_literal: true

require "open3"
require "optparse"
require "tmpdir"

require "ledger"
require "ledger/derive"
require "ledger/help"
require "ledger/read"
require "ledger/render/markdown"

module Ledger
    # The command line (docs/journal.md, section 4): `bin/ledger WORD
    # ARGS...`, one class per word in lib/ledger/commands/. Exit status:
    # 0 done, 1 a check that fails, 2 a refusal or a usage error, with
    # nothing written.
    #
    #     exit Ledger::CLI.run(ARGV)
    class CLI
        WORDS = %w[new goal check show status close fact assume constraint
                   decide noticed criterion edit piece ask answer word choice
                   renumber undo restore inbox take mockup survey stats].freeze
        # Words of other pieces of the build: refused as not built yet.
        NOT_BUILT = [].freeze

        def self.run(argv, out: $stdout, err: $stderr)
            new(out:, err:).run(argv)
        end

        def initialize(out:, err:)
            @out = out
            @err = err
        end

        # What asks for help in place of WORD.
        HELP = %w[help --help -h].freeze

        def run(argv)
            word, *words = argv
            return help(words) if word.nil? || HELP.include?(word)
            return refuse(word, "not built yet") if NOT_BUILT.include?(word)
            return unknown(word) unless WORDS.include?(word)

            dispatch(word, words)
        end

        private

        def dispatch(word, words)
            Commands.const_get(word.capitalize)
                    .new(words, out: @out, err: @err).call
        rescue Worse => e
            e.message.lines(chomp: true).each { @err.puts refused(word, it) }
            2
        rescue Refused, OptionParser::ParseError => e
            refuse(word, e.message)
        rescue Sequel::ConstraintViolation => e
            refuse(word, "refused, #{e.message}")
        end

        # A line "FAIL rule -- detail" of a Worse, as the refusal quotes it.
        def refused(word, line)
            "#{word}: refused, #{line.delete_prefix("FAIL ")}"
        end

        def refuse(word, message)
            @err.puts "#{word}: #{message}"
            2
        end

        # ledger help [WORD]: the words listed, or WORD's own help, as an
        # answer (exit 0) rather than a usage error; ledger alone too.
        def help(words)
            word, = words
            unless word
                @out.puts Help.overview
                return 0
            end
            return unknown(word) unless WORDS.include?(word)

            dispatch(word, ["--help"])
        end

        def unknown(word)
            refuse(word, "unknown command (ledger help lists the words)")
        end

        # The write path as a command uses it: the one Write.run, what a write
        # prints, the diff of a dry run and the numbered items every adder
        # shares.
        module Writing
            private

            def write(path, own: nil, &)
                opts = { own:, dry: @opts.fetch(:dry_run, false),
                         checks: Checks }
                Write.run(journal, path, self.class.word, @words, **opts, &)
            end

            # A new item of KIND (F, C, X, D): its next n, its row in TABLE and
            # its id printed first; the block adds what else the row needs
            # (edges), given the change and the id. OWN names the item in a
            # failure, the id by default.
            def add_item(path, kind, table, own: nil, **columns)
                result = write(path, own:) do |change|
                    ref = "#{kind}#{change.next_id(kind)}"
                    change.own = ref unless own
                    change.insert(table, n: ref[1..].to_i, **columns)
                    yield change, ref if block_given?
                    ref
                end
                line = Render::Markdown.line(result.after, result.value)
                emit(result, path, first: result.value, lines: [line])
                0
            end

            # What a write prints: the id it gave, the diff of a dry run,
            # the item's lines, the status line last.
            def emit(result, path, first: nil, lines: [])
                @out.puts first if first
                dry_report(result, path) if result.dry
                lines.each { @out.puts it }
                @out.puts status_line(result.after)
            end

            def dry_report(result, path)
                before = Render::Markdown.render(result.before)
                after = Render::Markdown.render(result.after)
                @out.print unified(before, after, Address.parse(path).to_s)
                @out.puts "dry run: nothing written"
            end

            def unified(before, after, address)
                Dir.mktmpdir("ledger-diff") do |dir|
                    files = { "before" => before,
                              "after" => after }.map do |name, text|
                        File.join(dir, name).tap { File.write(it, text) }
                    end
                    Open3.capture2("diff", "-u", "-L", address, "-L",
                                   "#{address} (after)", *files).first
                end
            end
        end

        # What every command shares: its words and options, the journal,
        # the refusals, and the one write path with its diff and status.
        class Command
            include Writing

            USAGE = ""
            # The arguments as the help shows them, USAGE by default;
            # USAGE alone counts the arguments.
            SYNOPSIS = nil
            # What the word does, one line, in the help's list and atop
            # its own help.
            SUMMARY = ""
            # The options that keep their value as given: key => [switch,
            # what the help says of it].
            OPTIONS = {}.freeze
            # What the help says of every --date.
            DATE = "the date, YYYY-MM-DD (today by default)"

            def self.word = name.split("::").last.downcase
            def self.synopsis = self::SYNOPSIS || self::USAGE

            def initialize(words, out:, err:)
                @words = words
                @out = out
                @err = err
                @opts = {}
            end

            # The word run, or its help printed (exit 0) when -h or
            # --help is among its words, whatever else they hold.
            def call
                parser = OptionParser.new(banner)
                values(parser)
                flags(parser)
                help(parser)
                catch(:help) { run(*arguments(parser.parse(@words))) }
            ensure
                @journal&.close
            end

            private

            def banner
                "usage: ledger #{self.class.word} #{self.class.synopsis}" \
                    "\n\n#{Help.wrap(self.class::SUMMARY, 78)}\n\nOptions:"
            end

            # OptionParser's own --help prints and exits the process; this
            # one prints to the command's output and returns 0.
            def help(parser)
                parser.on_tail("-h", "--help", "this help") do
                    @out.puts parser.help
                    throw :help, 0
                end
            end

            def values(parser)
                self.class::OPTIONS.each do |key, (switch, what)|
                    parser.on(switch, what) { @opts[key] = it }
                end
            end

            def flags(_parser) = nil

            def dry_run(parser)
                parser.on("--dry-run", "print the diff; write nothing") do
                    @opts[:dry_run] = true
                end
            end

            def arguments(args)
                tokens = self.class::USAGE.split
                required = tokens.count { !it.start_with?("[") }
                return args if args.size.between?(required, tokens.size)

                refuse("usage: ledger #{self.class.word} #{self.class::USAGE}")
            end

            def journal = @journal ||= Journal.open
            def refuse(message) = raise(Refused, message)

            # The option NAME, refused when it was not given.
            def need(name)
                @opts.fetch(name) { refuse("--#{name} is required") }
            end

            # TEXT stripped, refused when empty or holding a line break.
            def line(text, what)
                text = text.to_s.strip
                refuse("#{what} is empty") if text.empty?
                refuse("#{what} holds a line break") if text.match?(/[\r\n]/)
                text
            end

            def snapshot(path)
                Snapshot.read(journal.db, journal.ledger(path)[:id])
            end

            def status_line(snapshot)
                derive = Derive.read(journal.db, snapshot)
                Derive::StatusLine.new(derive).to_s
            end
        end
    end
end

require "ledger/commands/new"
require "ledger/commands/goal"
require "ledger/commands/check"
require "ledger/commands/show"
require "ledger/commands/status"
require "ledger/commands/close"
require "ledger/commands/fact"
require "ledger/commands/assume"
require "ledger/commands/constraint"
require "ledger/commands/decide"
require "ledger/commands/noticed"
require "ledger/commands/criterion"
require "ledger/commands/edit"
require "ledger/commands/piece"
require "ledger/commands/ask"
require "ledger/commands/answer"
require "ledger/commands/word"
require "ledger/commands/choice"
require "ledger/commands/renumber"
require "ledger/commands/undo"
require "ledger/commands/restore"
require "ledger/commands/inbox"
require "ledger/commands/take"
require "ledger/commands/mockup"
require "ledger/commands/survey"
require "ledger/commands/stats"
