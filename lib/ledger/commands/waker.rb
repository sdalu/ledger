# frozen_string_literal: true

require "ledger/waker"

module Ledger
    module Commands
        # `waker PATH on|off`: the ledger switched on for the waker
        # (bin/ledger-waker), or off; off by default. One event, `waker`,
        # which undo takes back.
        class Waker < CLI::Command
            USAGE = "PATH WORD"
            SYNOPSIS = "PATH on|off"
            SUMMARY = "let bin/ledger-waker wake an idle session when an " \
                      "entry of yours waits on this ledger, or stop it"
            WORDS = { "on" => true, "off" => false }.freeze

            private

            def run(path, word)
                on = WORDS.fetch(word) do
                    refuse("on or off, not #{word.inspect}")
                end
                result = Ledger::Waker.switch(journal, path, on)
                @out.puts "waker #{word}: #{Address.parse(path)}"
                @out.puts status_line(result.after)
                0
            end
        end
    end
end
