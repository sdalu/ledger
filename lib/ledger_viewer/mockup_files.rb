# frozen_string_literal: true

module LedgerViewer
    # A ledger's pictures, from the journal: /m/ID/NAME for a picture of
    # one file, /m/ID/NAME/PATH for a file of one placed as a directory
    # (a NAME may hold a slash: the longest that leads the rest is the
    # one), behind sign-in; and the same under a key in the path,
    # /m/k/TOKEN/ID/NAME[/PATH] (MockupToken), for the frame of a mockup,
    # which sends no session. A Sinatra extension registered on Web.
    module MockupFiles
        # The path of a file under a key: the token, the ledger's id, the
        # rest.
        KEYED = %r{\A/m/k/([^/]+)/([0-9a-f]{10})/(.+)\z}

        def self.registered(app)
            app.helpers Helpers
            app.get(%r{/m/([0-9a-f]{10})/(.+)}) do |lid, rest|
                picture(lid, rest)
            end
            # A page swapped in by a live update carries a fresh key.
            app.get(%r{/m/k/([^/]+)/([0-9a-f]{10})/(.+)}) do |_key, lid, rest|
                picture(lid, rest)
            end
        end

        # What the routes and the `before` filter use.
        module Helpers
            # Whether this request is a GET of a file under a valid key,
            # which the `before` filter then admits without a session. A
            # bad or expired key goes on to the session check when a
            # session is held (the file is then served as /m/ serves
            # it); without one it is a 404, not a sign-in prompt.
            def keyed_mockup!
                key = KEYED.match(request.path_info) if request.get?
                return false unless key

                secret = settings.config.session_secret
                return true if MockupToken.valid?(secret, key[1], key[2])
                return false unless signed_out?

                not_found
            end

            # The file REST names under ledger LID, with the mockup policy.
            def picture(lid, rest)
                entry = settings.ledgers.find(lid) or not_found
                row = settings.ledgers.picture_at(entry, unquoted(rest)) or
                    not_found
                headers Headers::MOCKUP
                content_type row[:type]
                row[:bytes].to_s
            end
        end
    end
end
