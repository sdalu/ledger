# frozen_string_literal: true

require "sesam"

module LedgerViewer
    # The lan setting: the networks whose callers need no sign-in.
    module Lan
        # `given` as sesam reads networks (192.0.2.0/24, ::1/128, one
        # address); one that does not parse is refused at boot, not at
        # the first request.
        def self.networks(given)
            Sesam::Networks.new(given, "lan").to_a
        rescue Sesam::Networks::Error => e
            raise ConfigError, e.message
        end
    end
end
