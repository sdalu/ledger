# frozen_string_literal: true

require "json"

module Ledger
    # The hooks (docs/journal.md, section 7): `bin/ledger hook NAME` reads
    # the hook payload on stdin and answers on stdout and by exit
    # status as the harness expects. This file is the dispatcher and
    # needs the standard library alone, so the two hooks that read no
    # journal (heartbeat, journal-write) start without bundler; each
    # hook's file is required when it runs.
    #
    #     exit Ledger::Hooks.main(["heartbeat"])
    module Hooks
        # Hook word => the constant its file defines.
        NAMES = { "heartbeat" => :Heartbeat,
                  "brief-constraints" => :BriefConstraints,
                  "journal-write" => :JournalWrite,
                  "finish" => :Finish,
                  "inbox" => :Inbox,
                  "session-start" => :SessionStart }.freeze

        # What a hook answers: the text for stdout, the text for stderr,
        # the exit status (2 refuses, on the events that take a refusal).
        Answer = Data.define(:out, :err, :status) do
            def self.pass = new(out: nil, err: nil, status: 0)

            def self.json(doc)
                new(out: JSON.generate(doc), err: nil, status: 0)
            end

            def self.refuse(text) = new(out: nil, err: text, status: 2)
        end

        module_function

        # -> the exit status. An unknown hook word is the launcher's
        # misuse: exit 1, which no event reads as a refusal.
        def main(argv, input: $stdin, out: $stdout, err: $stderr)
            name = argv.first
            unless NAMES.key?(name)
                err.puts "ledger hook: no hook #{name.inspect}; " \
                         "one of #{NAMES.keys.join(", ")}"
                return 1
            end
            answer = answer(name, input.binmode.read)
            out.puts answer.out if answer.out
            err.puts answer.err if answer.err
            answer.status
        end

        # Any error of the hook's own is a silent pass: a hook never
        # blocks a session, a dispatch or a command on its own failure.
        def answer(name, text)
            payload = JSON.parse(text.force_encoding(Encoding::UTF_8))
            return Answer.pass unless payload.is_a?(Hash)

            require "ledger/hooks/#{name.tr("-", "_")}"
            const_get(NAMES.fetch(name)).call(payload)
        rescue StandardError, ScriptError
            Answer.pass
        end
    end
end
