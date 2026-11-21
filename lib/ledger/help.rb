# frozen_string_literal: true

module Ledger
    # What `ledger help`, `ledger --help` and `ledger` alone print: the
    # words in sections, each with its arguments and summary (the
    # command's SYNOPSIS and SUMMARY), then the notes every word shares.
    module Help
        WIDTH = 78
        # The column the summaries start at; a longer synopsis puts its
        # summary on the next line.
        COLUMN = 30

        SECTIONS = {
            "A ledger" => %w[new goal close],
            "Reading" => %w[check show status],
            "Items" => %w[fact constraint decide noticed criterion edit],
            "Pieces and questions" => %w[piece ask choice mockup],
            "The user's word" => %w[inbox take answer word],
            "History" => %w[renumber undo restore]
        }.freeze

        NOTES = <<~TEXT
            PATH is the ledger's address, the path its file would have
            (.claude/LEDGER.md or LEDGER-NAME.md); the journal holds it, nothing is
            written there. Every writer but new, take, close and mockup takes
            --dry-run, which prints the diff and writes nothing.

            ledger help WORD, or ledger WORD --help, gives the word's options.

            Exit status: 0 done, 1 a check that fails (or a wait that timed out),
            2 a refusal or a usage error, nothing written.

            The launcher also runs the session's hooks: ledger hook NAME
            (docs/journal.md, section 7).
        TEXT

        module_function

        def overview
            sections = SECTIONS.map do |title, words|
                "#{title}:\n#{words.map { entry(it) }.join("\n")}"
            end
            "Usage: ledger WORD PATH [ARGS] [OPTIONS]\n\n" \
                "#{sections.join("\n\n")}\n\n#{NOTES}"
        end

        # One word's line: its synopsis, its summary wrapped in the column.
        def entry(word)
            command = Commands.const_get(word.capitalize)
            head = "  #{word} #{command.synopsis}"
            body = wrap(command::SUMMARY, WIDTH - COLUMN)
                   .gsub("\n", "\n#{" " * COLUMN}")
            return "#{head.ljust(COLUMN)}#{body}" if head.size < COLUMN - 1

            "#{head}\n#{" " * COLUMN}#{body}"
        end

        # TEXT broken at spaces into lines of at most WIDTH characters.
        def wrap(text, width)
            text.split.each_with_object([]) do |token, lines|
                if lines.empty? || lines.last.size + 1 + token.size > width
                    lines << token.dup
                else
                    lines.last << " " << token
                end
            end.join("\n")
        end
    end
end
