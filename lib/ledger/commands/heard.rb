# frozen_string_literal: true

require "ledger/transcript"

module Ledger
    module Commands
        # The user's words traced to the user's own messages in this
        # session's transcript. A word (`word`, `answer`, `decide --by
        # user`) without the viewer's entry is refused unless the user
        # wrote after the item was asked: a session cannot give itself
        # the word it waits for. A quote (`new --goal`, `goal --quote`,
        # `constraint`) not found in a message of the user's is warned
        # of, unless `--said-in` says where it was said. No transcript
        # found: a warning, and the command goes on.
        module Heard
            TIME = "%Y-%m-%d %H:%M:%S"
            SAID_IN = ["--said-in WHERE",
                       "where the user said the quote, when this " \
                       "session's transcript does not hold it"].freeze

            private

            # Refused unless the user wrote after SINCE (ms).
            def heard!(since)
                found = transcript or return unchecked("word")
                return if found.heard_since?(since)

                refuse("no message of the user's in this session's " \
                       "transcript since #{stamp(since)}: the word is " \
                       "theirs to give; file it once they give it, or " \
                       "take the viewer's entry (--take N<n>)")
            end

            # A warning unless QUOTE stands in a message of the user's or
            # --said-in names where it was said.
            def quoted!(quote)
                return if @opts[:said_in]

                found = transcript or return unchecked("quote")
                return if found.quoted?(quote)

                warning("the quote is in no message of the user's in this " \
                        "session's transcript: quote their words verbatim, " \
                        "or say where they said it with --said-in WHERE")
            end

            # --said-in's WHERE, refused when empty or holding a line
            # break; nil when not given.
            def said_in
                where = @opts[:said_in] or return

                line(where, "--said-in")
            end

            def transcript
                return @transcript if defined?(@transcript)

                @transcript = Transcript.current
            end

            def unchecked(what)
                warning("no transcript of this session found " \
                        "(CLAUDE_CODE_SESSION_ID unset or its file absent); " \
                        "the #{what} is not checked")
            end

            def warning(text)
                @err.puts("#{self.class.word}: warning: #{text}")
            end

            def stamp(ms)
                return "its start" if ms <= 0

                Time.at(ms / 1000).strftime(TIME)
            end
        end
    end
end
