# frozen_string_literal: true

module Ledger
    module Hooks
        # The command texts a shell text runs inside itself: `$( )`,
        # `<( )`, `>( )` and backticks, outermost ones only (the caller
        # reads each text in turn, which finds the ones within). Quotes
        # are not told apart, so a substitution in single quotes is read
        # too: a command that only looks like one is read as one.
        #
        #     Substitutions.in("echo $(rm j) `ls`")  # => ["rm j", "ls"]
        module Substitutions
            OPENER = /[$<>]\(/

            def self.in(text)
                found = []
                at = 0
                while (start = text.index(/[`$<>]/, at))
                    inner, at = read(text, start)
                    found << inner if inner
                end
                found
            end

            # -> [inner text or nil, index to go on from].
            def self.read(text, start)
                if text[start] == "`"
                    close = text.index("`", start + 1) || text.size
                    [text[(start + 1)...close], close + 1]
                elsif OPENER.match?(text[start, 2])
                    close = closing(text, start + 2)
                    [text[(start + 2)...close], close + 1]
                else
                    [nil, start + 1]
                end
            end

            # The index of the parenthesis closing the one opened before
            # FROM, or the text's end.
            def self.closing(text, from)
                depth = 1
                (from...text.size).each do |at|
                    depth += { "(" => 1, ")" => -1 }.fetch(text[at], 0)
                    return at if depth.zero?
                end
                text.size
            end
        end
    end
end
