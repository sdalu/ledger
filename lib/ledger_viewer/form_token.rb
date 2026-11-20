# frozen_string_literal: true

require "openssl"

module LedgerViewer
    # The hidden field every form of a ledger page carries: one per
    # session, so that a page of another site, which cannot read this
    # viewer's pages, cannot name it, and a restart of the server does
    # not void the pages already open. The POST that takes the form
    # derives it again from the same session and compares.
    module FormToken
        # `held` is the session the request holds (Sesam::Session::Held),
        # or nil for a caller with no session, whose forms then carry a
        # token no session can ever match.
        def self.for(secret, held)
            who = held ? "#{held.name}:#{held.issued}" : "-"
            OpenSSL::HMAC.hexdigest("SHA256", secret, "form-token:#{who}")
        end
    end
end
