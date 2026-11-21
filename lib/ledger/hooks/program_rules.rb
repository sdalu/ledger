# frozen_string_literal: true

module Ledger
    module Hooks
        # What one program does to the journal, by its arguments (the
        # words after the program, redirects left out): tee, mv, rm
        # naming it; cp or install onto it; sqlite3 on it without
        # -readonly; sed, perl or ruby in place on it; python, ruby or
        # perl code that names it and opens or writes a file.
        #
        #     ProgramRules.new(name).call("sqlite3", args)  # => word | nil
        class ProgramRules
            # Flags that take the rest of the cluster as their argument.
            ARG_FLAGS = { "sed" => "efl", "perl" => "eEIMmFlx0",
                          "ruby" => "reIEFCx0" }.freeze
            INTERPRETER = /\A(?:python|ruby|perl)/
            READONLY = %w[-readonly --readonly].freeze
            CODE_OPEN = Regexp.union(
                /sqlite3?\.connect/, /SQLite3::Database/,
                /Sequel\.(?:sqlite|connect)/, /DBI\s*->\s*connect/,
                /\bopen\b/, /\.write_(?:text|bytes)\b/,
                /\b(?:File|IO)\.(?:write|binwrite|open|delete|unlink|rename|
                   truncate)\b/x,
                /\bFileUtils\b/, /\bos\.(?:remove|unlink|rename|replace)\b/,
                /\bshutil\./, /\bunlink\b/
            )

            def initialize(name)
                @name = name
            end

            # -> the journal word PROGRAM writes with ARGS (Words::Word
            # values), or nil.
            def call(program, args)
                plain = args.reject { it.quoted && it.text.match?(/\s/) }
                            .map(&:text)
                hits = plain.grep(@name)
                simple(program, plain, hits) ||
                    in_place(program, plain, hits) ||
                    code(program, args, hits)
            end

            private

            def simple(program, plain, hits)
                case program
                when "tee", "mv", "rm" then hits.first
                when "cp", "install"
                    plain.last if plain.last && @name.match?(plain.last)
                when "sqlite3" then hits.first unless plain.intersect?(READONLY)
                end
            end

            # sed -i, perl -pi, ruby -i.bak.
            def in_place(program, plain, hits)
                stops = ARG_FLAGS[program]
                return unless stops && hits.any?
                hits.first if plain.any? { in_place_flag?(it, stops) }
            end

            # The in-place flag before any flag that takes the rest of the
            # cluster (`-ie` is in place, `-ei` is code).
            def in_place_flag?(word, stops)
                return false unless word.match?(/\A-[^-]/)
                flag = word.index("i", 1)
                stop = word.index(/[#{Regexp.escape(stops)}]/, 1)
                !flag.nil? && (stop.nil? || flag < stop)
            end

            # Interpreter code naming the journal and opening or writing a
            # file; or the journal as an argument of such code.
            def code(program, args, hits)
                return unless INTERPRETER.match?(program)
                found = args.lazy.filter_map { opened(it.text) }.first
                return found if found
                hits.first if args.any? { CODE_OPEN.match?(it.text) }
            end

            def opened(code)
                @name.mentions(code).first if CODE_OPEN.match?(code)
            end
        end
    end
end
