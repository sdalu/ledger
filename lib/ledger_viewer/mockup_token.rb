# frozen_string_literal: true

require "openssl"
require "rack/utils"

module LedgerViewer
    # The key a page carries in the path of a mockup's files
    # (/m/k/TOKEN/LID/NAME[/PATH]). A mockup's page runs in a sandboxed
    # frame with an opaque origin, so its requests (the page, then its
    # CSS, scripts and images) carry no session cookie; the key stands in
    # for it, for one ledger and for an hour. It reads files and nothing
    # else, and a page is only issued keys for an admitted caller.
    #
    # TOKEN is `base64url("LID.EXPIRY")` + "." + `base64url(HMAC)`, the
    # HMAC-SHA256 of "mockup\0LID\0EXPIRY" under the session secret (the
    # one FormToken uses), EXPIRY unix seconds.
    module MockupToken
        TTL = 3600
        # The shape a path's token segment must have to be looked at.
        SHAPE = /\A[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\z/

        module_function

        # The token for LID, good for TTL seconds from NOW.
        def issue(secret, lid, now: Time.now)
            expiry = now.to_i + TTL
            "#{encode("#{lid}.#{expiry}")}.#{encode(mac(secret, lid, expiry))}"
        end

        # Whether TOKEN is one `issue` made for LID with the same SECRET,
        # not yet expired at NOW.
        def valid?(secret, token, lid, now: Time.now)
            return false unless SHAPE.match?(token.to_s)

            payload, given = token.split(".")
            who, expiry = decode(payload).split(".", 2)
            return false unless who == lid && /\A\d+\z/.match?(expiry)

            Rack::Utils.secure_compare(encode(mac(secret, lid, expiry.to_i)),
                                       given) && expiry.to_i > now.to_i
        rescue ArgumentError
            false
        end

        def mac(secret, lid, expiry)
            OpenSSL::HMAC.digest("SHA256", secret, "mockup\0#{lid}\0#{expiry}")
                         .byteslice(0, 32)
        end

        def encode(bytes) = [bytes].pack("m0").tr("+/", "-_").delete("=")

        def decode(text)
            padded = text.ljust((text.length + 3) / 4 * 4, "=")
            padded.tr("-_", "+/").unpack1("m0")
        end
    end
end
