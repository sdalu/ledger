# frozen_string_literal: true

# user.rake -- who may sign in, from the command line: a user invited
# (its one-time URL printed), the users listed, a user removed.
#
#   rake user:invite NAME=alice   made if new; prints the URL, once
#   rake user:list                each user: password, passkeys, invitation
#   rake user:remove NAME=alice   the user, their passkeys and sessions gone

namespace :user do
    # The configuration and sesam's users in the journal, loaded on
    # demand: `rake -T` must not need the journal.
    def user_store
        require "ledger_viewer"
        config = LedgerViewer::Config.load
        journal = LedgerViewer::Accounts.journal
        [config, LedgerViewer::Accounts.open(journal)]
    end

    def user_name(task)
        ENV.fetch("NAME", nil) or
            abort("user:#{task}: say who -- rake user:#{task} NAME=alice")
    end

    def user_line(row)
        invite = row.invite ? "invited until #{row.invite.strftime("%F")}" : nil
        [row.name, row.password ? "password" : "no password",
         "#{row.passkeys} passkey(s)", invite].compact.join("  ")
    end

    desc "Invite a user (made if new): rake user:invite NAME=alice"
    task :invite do
        name = user_name("invite")
        config, store = user_store
        token = LedgerViewer::Accounts.invite(store, name)
        scheme = config.tls ? "https" : "http"
        puts "Open once, within 7 days:"
        puts "#{scheme}://#{config.bind.first}/invite##{token}"
    end

    desc "List the users: password, passkeys, open invitation"
    task :list do
        _, store = user_store
        rows = Sesam::Users.new(store).list
        puts(rows.empty? ? "no users" : rows.map { user_line(it) })
    end

    desc "Remove a user and their passkeys and sessions: NAME=alice"
    task :remove do
        name = user_name("remove")
        _, store = user_store
        Sesam::Users.new(store).remove(name)
        puts "removed #{name}"
    rescue Sesam::Users::Error => e
        abort("user:remove: #{e.message}")
    end
end
