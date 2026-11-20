# frozen_string_literal: true

# invite.rake -- the way a user is first let in: an invitation made
# from the command line, its one-time URL printed.

desc "Invite a user (made if new): rake invite NAME=alice"
task :invite do
    name = ENV.fetch("NAME", nil) or
        abort("invite: say who -- rake invite NAME=alice")
    require "ledger_viewer"

    config = LedgerViewer::Config.load
    db = LedgerViewer::Accounts.open(config)
    token = LedgerViewer::Accounts.invite(db, name)
    host = config.bind.first
    puts "Open once, within 7 days:"
    puts "http://#{host}/invite##{token}"
end
