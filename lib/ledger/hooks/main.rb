# frozen_string_literal: true

require "json"

module Ledger
    # The hooks (docs/journal.md, section 7): `bin/ledger hook NAME` reads
    # the hook payload on stdin and answers on stdout and by exit
    # status as the harness expects. This file is the dispatcher and
    # needs the standard library alone, so the hooks that need no bundle
    # (heartbeat, journal-write, stamp) start without bundler; each
    # hook's file is required when it runs.
    #
    #     exit Ledger::Hooks.main(["heartbeat"])
    module Hooks
        # Hook word => the constant its file defines.
        NAMES = { "heartbeat" => :Heartbeat,
                  "brief-constraints" => :BriefConstraints,
                  "brief-piece" => :BriefPiece,
                  "journal-write" => :JournalWrite,
                  "finish" => :Finish,
                  "inbox" => :Inbox,
                  "edit-record" => :EditRecord,
                  "commit-record" => :CommitRecord,
                  "word-gate" => :WordGate,
                  "uncommitted" => :Uncommitted,
                  "session-start" => :SessionStart,
                  "status-stop" => :StatusStop,
                  "one-list" => :OneList,
                  "viewer-guard" => :ViewerGuard,
                  "stamp" => :Stamp }.freeze

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
            answer = const_get(NAMES.fetch(name)).call(payload)
            denied(name, payload, answer)
            answer
        rescue StandardError, ScriptError
            Answer.pass
        end

        # A PreToolUse deny recorded as a refusal under the hook's name,
        # its reason the detail; the recorder never raises nor prints
        # here, so the answer stays the hook's.
        def denied(name, payload, answer)
            reason = deny_reason(answer) or return

            require "ledger/outcomes"
            Outcomes.record(kind: "refusal", rule: name, detail: reason,
                            places: Places.of(payload),
                            session: Outcomes.session(payload), err: nil)
        rescue StandardError, ScriptError
            nil
        end

        # The reason of an answer that denies; nil for any other.
        def deny_reason(answer)
            output = answer.out && JSON.parse(answer.out)["hookSpecificOutput"]
            return unless output.is_a?(Hash) &&
                          output["permissionDecision"] == "deny"

            output["permissionDecisionReason"].to_s
        end
    end
end
