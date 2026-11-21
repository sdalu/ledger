# frozen_string_literal: true

require "ledger/inbox"
require "ledger/hooks/ledgers"

module Ledger
    module Hooks
        # Stop: what the user wrote in the viewer reaches the session
        # before it stops. Entries no take has recorded refuse the stop
        # once, verbatim, with the filing steps; on the retry
        # (stop_hook_active) the stop goes through, so a session that
        # cannot file an entry is never held.
        module Inbox
            STEPS = "The user wrote in the ledger viewer; these are their " \
                    "words, verbatim (orchestration, The inbox). File each " \
                    "in the ledger before you stop: an answer to O<n> as a " \
                    "Decision by user quoting it (the option chosen and " \
                    "every comment, per option or per item too), O<n> then " \
                    "removed from Open (`bin/ledger answer ADDRESS O<n> " \
                    "--decision ... --take N<n>` does both and the take); a " \
                    "comment on a planned piece into that piece's brief or " \
                    "as a Decision by user; a comment on a piece awaiting " \
                    "the user's word (sent without the word) answered in " \
                    "your reply and filed as a Decision by user, the word " \
                    "still awaited; a proposed order as the order you " \
                    "dispatch in, recorded as a Decision by user; a word on " \
                    "a piece (start, commit, deploy, push, merge, other, " \
                    "drop) as a Decision by user with the piece changed in " \
                    "the same write (`bin/ledger word ADDRESS P<n> --word W " \
                    "--take N<n>`), then acted on; drop closes the item " \
                    "with no follow-up (a question out of Open; a piece set " \
                    "dropped, its delegate stopped, nothing of it " \
                    "committed, nothing raised again); a note where it " \
                    "belongs (Constraint, Decision, Open, a piece), quoted. " \
                    "Then run `bin/ledger take ADDRESS N<n>...` for those " \
                    "filed, and tell the user what you did with each."

            module_function

            def call(payload)
                return Answer.pass if payload["stop_hook_active"]
                parts = parts(Ledgers.read(payload))
                return Answer.pass if parts.empty?
                Answer.refuse("#{STEPS}\n#{parts.join("\n")}")
            end

            # "ADDRESS:\n" and the pending entries, per ledger that has any.
            def parts(found)
                found.filter_map do |ledger|
                    rows = ledger.derive.pending_entries
                    next if rows.empty?
                    "#{ledger.address}:\n" \
                        "#{rows.map { Ledger::Inbox.show(it) }.join("\n")}"
                end
            end
        end
    end
end
