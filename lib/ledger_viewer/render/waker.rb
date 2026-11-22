# frozen_string_literal: true

module LedgerViewer
    module Render
        # The waker's part of a ledger page head: its switch, a form the
        # page's script leaves alone, and the wakes it made, newest
        # first (time, path, outcome), folded under their count.
        class Waker
            def initialize(scope, lid, token)
                @scope = scope
                @lid = lid
                @token = token
            end

            # WAKING: the viewer's Ledgers::Waking of the ledger.
            def html(waking)
                @scope.partial("ledger/waker",
                               lid: @lid, token: @token, on: waking.on,
                               wakes: waking.wakes.map { row(it) })
            end

            # The head's line while the waker is off and COUNT sent entries
            # are unread: nothing wakes a session for them, with the switch
            # beside. "" when the waker is on or nothing is unread.
            def unread(waking, count)
                return "" if waking.on || count.zero?

                @scope.partial("ledger/waker_unread",
                               lid: @lid, token: @token, count:)
            end

            private

            def row(wake)
                { at: Time.at(wake[:at] / 1000).strftime("%Y-%m-%d %H:%M"),
                  path: wake[:path], outcome: wake[:outcome] }
            end
        end
    end
end
