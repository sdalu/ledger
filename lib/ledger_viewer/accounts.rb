# frozen_string_literal: true

require "fileutils"

require "sesam"

module LedgerViewer
    # Who may sign in: sesam's users, invitations and passkeys in a
    # JSON file at the configured path.
    module Accounts
        APP = "ledger-viewer"

        # The store, its directory made mode 700 when missing; the file
        # itself appears at the first write.
        def self.open(config)
            FileUtils.mkdir_p(config.data_dir, mode: 0o700)
            Sesam::JsonStore.new(config.store)
        end

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
