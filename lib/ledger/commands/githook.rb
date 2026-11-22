# frozen_string_literal: true

require "ledger/githook"

module Ledger
    module Commands
        # `githook install|uninstall PATH`, and `githook check`, which
        # the installed hook runs.
        class Githook < CLI::Command
            USAGE = "ACTION [PATH]"
            SYNOPSIS = "install|uninstall PATH"
            ACTIONS = %w[install uninstall].freeze
            SUMMARY = "install, or remove, the git pre-commit hook of the " \
                      "repository at PATH: a commit from a Claude session " \
                      "(CLAUDECODE set) is refused unless the gate stamped " \
                      "its staged tree (gate-stamp), any other commit is " \
                      "warned of that and goes through. An existing " \
                      "pre-commit hook is chained, and put back by " \
                      "uninstall. The hook runs `githook check`"

            private

            def run(action, path = nil)
                return Ledger::Githook.check(Dir.pwd, err: @err) if
                    action == "check"

                refuse("usage: ledger githook #{self.class::SYNOPSIS}") unless
                    path && ACTIONS.include?(action)

                @out.puts Ledger::Githook.public_send(action, path)
                0
            end
        end
    end
end
