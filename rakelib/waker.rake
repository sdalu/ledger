# frozen_string_literal: true

# waker.rake -- what the waker needs in the user's Claude Code settings,
# merged in or taken out (Ledger::WakerInstall), and its probe directory.
#
#   rake waker:install     the hooks and crossSessionInbound, the probe dir
#   rake waker:uninstall   what install added, taken out
#   rake check:waker       whether the waker can wake a session here
#
# SETTINGS=PATH names another settings file (default ~/.claude/settings.json).

namespace :waker do
    def waker_settings
        File.expand_path(ENV.fetch("SETTINGS", "~/.claude/settings.json"))
    end

    desc "Merge the waker's hooks and crossSessionInbound into the settings"
    task :install do
        require "ledger/waker_install"
        done = Ledger::WakerInstall.install(waker_settings)
        puts(done.empty? ? "settings: nothing to change" : done)
        FileUtils.mkdir_p(Ledger::WakerInstall::PROBE)
        puts "left to you: start claude once in " \
             "#{Ledger::WakerInstall::PROBE} and trust it (for --probe), " \
             "restart the sessions to wake, then bin/ledger-waker and " \
             "ledger waker PATH on"
    end

    desc "Take out of the settings what waker:install added"
    task :uninstall do
        require "ledger/waker_install"
        done = Ledger::WakerInstall.uninstall(waker_settings)
        puts(done.empty? ? "settings: nothing to take out" : done)
    end
end

namespace :check do
    desc "Report whether the waker can wake a session here (warn only)"
    task :waker do
        require "ledger/journal"
        require "ledger/waker_check"
        Preflight.title("the waker")
        Ledger::WakerCheck.new(
            root: File.expand_path("..", __dir__),
            journal: Ledger::Journal.path,
            settings: Ledger::WakerCheck::Settings.new(waker_settings)
        ).lines.each { Preflight.item(*it) }
    end
end
