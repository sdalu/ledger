# frozen_string_literal: true

module Ledger
    module Hooks
        # A shell command as words, the way the journal-write hook reads
        # it: quotes respected (a quoted word is marked), `;` `&` `|`
        # and newline as breaks between segments, `<`/`>` runs as words of
        # their own, a heredoc's body one quoted word of the command it
        # feeds. Not a shell parser: enough to find the program of each
        # segment and the paths it names.
        #
        #     Words.segments("cat a > b; sh -c 'x'")
        #     # => [[cat, >, b], [sh, -c, x(quoted)]]
        class Words
            Word = Data.define(:text, :quoted)
            BREAK = Word.new(text: "\n", quoted: false)
            ACTIONS = { "'" => :quote, '"' => :quote, "\\" => :escape,
                        " " => :blank, "\t" => :blank,
                        ";" => :separator, "&" => :separator,
                        "|" => :separator, "\n" => :separator,
                        "<" => :angle, ">" => :redirect }.freeze

            def self.segments(command) = new(command).segments

            def initialize(command)
                @cmd = command
                @i = 0
                @out = []
                @heredocs = []
                reset
            end

            # The words between breaks, empty segments dropped.
            def segments
                tokens.chunk { it == BREAK ? :_separator : true }.map(&:last)
            end

            def tokens
                send(ACTIONS.fetch(@cmd[@i], :char)) while @i < @cmd.size
                flush
                @out
            end

            private

            def reset
                @cur = +""
                @quoted = false
            end

            def flush
                @out << Word.new(text: @cur, quoted: @quoted) unless
                    @cur.empty? && !@quoted
                reset
            end

            def char
                @cur << @cmd[@i]
                @i += 1
            end

            def blank
                flush
                @i += 1
            end

            # The text up to the closing quote, a backslash in double
            # quotes skipping the character after it.
            def quote
                mark = @cmd[@i]
                stop = @i + 1
                while stop < @cmd.size && @cmd[stop] != mark
                    stop += mark == '"' && @cmd[stop] == "\\" ? 2 : 1
                end
                @cur << (@cmd[(@i + 1)...stop] || "")
                @quoted = true
                @i = stop + 1
            end

            def escape
                return char if @i + 1 >= @cmd.size
                @cur << @cmd[@i + 1]
                @i += 2
            end

            # A run of `;&|` is one break; a newline also starts the body
            # of a heredoc waiting for one.
            def separator
                newline = @cmd[@i] == "\n"
                flush
                @i += 1 while @i < @cmd.size && ";&|".include?(@cmd[@i])
                if newline
                    @i += 1
                    heredoc_body unless @heredocs.empty?
                end
                @out << BREAK
            end

            def heredoc_body
                rest = @cmd[@i..]
                tag = Regexp.escape(@heredocs.shift)
                stop = /^[ \t]*#{tag}[ \t]*$/.match(rest)
                body = stop ? rest[0...stop.begin(0)] : rest
                @out << Word.new(text: body, quoted: true)
                @i += stop ? stop.end(0) : rest.size
            end

            def angle = @cmd[@i, 2] == "<<" ? heredoc : redirect

            # `<<TAG`, `<<-'TAG'`, `<<~"TAG"`: the tag is remembered for
            # the next newline.
            def heredoc
                flush
                at = @i + 2
                at += 1 while at < @cmd.size && "-~ ".include?(@cmd[at])
                tag = /\A['"]?(\w+)['"]?/.match(@cmd[at..])
                @heredocs << tag[1] if tag
                @i = tag ? at + tag.end(0) : at
            end

            def redirect
                flush
                stop = @i
                stop += 1 while stop < @cmd.size && "<>|&".include?(@cmd[stop])
                @out << Word.new(text: @cmd[@i...stop], quoted: false)
                @i = stop
            end
        end
    end
end
