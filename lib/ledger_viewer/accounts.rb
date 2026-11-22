# frozen_string_literal: true

require "sesam"

require "ledger"

module LedgerViewer
    # Who may sign in: sesam's users, invitations and passkeys, kept in
    # the journal (sesam's own tables, migrated by Journal.open).
    module Accounts
        APP = "ledger-viewer"

        # How long the viewer waits on a busy journal before it answers
        # 503.
        BUSY_MS = 2000

        # The journal LEDGER_JOURNAL names (else the default), opened for
        # the viewer: a busy one is waited on BUSY_MS.
        def self.journal = Ledger::Journal.open(busy_ms: BUSY_MS)

        # sesam's store on that journal.
        def self.open(journal) = Sesam::SequelStore.new(journal.db)

        # What sesam is told. Passwords only for now (passkeys come with
        # HTTPS); `lan` is the networks whose callers are admitted without
        # signing in, none unless the configuration names them.
        def self.settings(config, store)
            Sesam::Settings.new(
                store:, accept: %w[password],
                lan: config.lan, app: APP,
                session: Sesam::Session.new(
                    config.session_secret,
                    lifetime: config.session_days * 86_400
                )
            )
        end

        # An invitation for `name`, who is made a user first when new;
        # the token, shown once. The caller builds the URL.
        def self.invite(store, name)
            users = Sesam::Users.new(store)
            name = users.add(name) unless users.exists?(name)
            users.invite(name)
        end
    end
end
