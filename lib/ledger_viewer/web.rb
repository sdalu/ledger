# frozen_string_literal: true

require "sinatra/base"
require "sesam/sinatra"

module LedgerViewer
    # The viewer: /health open to anyone, the sign-in and invitation
    # pages, sesam's JSON routes, and behind the gate the index of the
    # journal's live ledgers, a ledger's page and its pictures, drawn by
    # Render. Pages and pictures carry their policy headers
    # (Headers). Errors are answers: show_exceptions and raise_errors
    # are off, 404 and 422 have pages, and a journal still busy after
    # Accounts::BUSY_MS is a 503.
    class Web < Sinatra::Base
        # Reachable without being admitted: the monitor's route, the two
        # pages a browser signs in through, and the stylesheet they use
        # (public/ is served before any filter, scripts included).
        PUBLIC = %w[/health /sign-in /invite /viewer.css].freeze

        register Sesam::Sinatra
        register Sends, WakerSwitch

        set :root, File.expand_path("../..", __dir__)
        set :erb, escape_html: true
        set :show_exceptions, false
        set :raise_errors, false
        set :absolute_redirects, false
        set :sessions, false
        set :config, nil
        set :ledgers, nil
        set :renderer, nil
        set :sender, nil
        set :host_authorization, lambda {
            config ? { permitted_hosts: config.permitted_hosts } : {}
        }

        if LedgerViewer.debug?
            set :show_exceptions, :after_handler
            set :logging, true
        end

        # The app for `config` over `journal`, a subclass of its own so
        # that two builds (two tests) never share settings.
        def self.configured(config, journal: Accounts.journal)
            ledgers = Ledgers.new(journal)
            renderer = Render::Renderer.new(config, ledgers)
            Class.new(self) do
                set config:, renderer:, ledgers:,
                    sender: Sender.new(ledgers),
                    sesam: Accounts.settings(config, Accounts.open(journal))
            end
        end

        before do
            same_site!
            next if PUBLIC.include?(request.path_info) || sesam_open?

            redirect to("/sign-in", false) if page? && signed_out?
            admit!
        end

        get "/health" do
            content_type :text
            "ok\n"
        end
        get("/sign-in") { erb :sign_in }
        get("/invite") { erb :invite }

        get "/" do
            page_headers
            settings.renderer.index
        end

        get %r{/l/([0-9a-f]{10})} do |lid|
            entry = settings.ledgers.find(lid) or not_found
            page_headers
            settings.renderer.ledger(entry, form_token)
        end

        # The links page of a piece or a decision: what led to it, what
        # it led to. An id the ledger does not hold is not found.
        get %r{/l/([0-9a-f]{10})/why/([PX][1-9]\d*)} do |lid, id|
            entry = settings.ledgers.find(lid) or not_found
            page_headers
            settings.renderer.links(entry, id)
        rescue LinksGraph::Error
            not_found
        end

        # A ledger's pictures, from the journal: /m/ID/NAME for a picture
        # of one file, /m/ID/NAME/PATH for a file of one placed as a
        # directory. A NAME may hold a slash: the longest that leads the
        # rest is the one.
        get %r{/m/([0-9a-f]{10})/(.+)} do |lid, rest|
            entry = settings.ledgers.find(lid) or not_found
            row = settings.ledgers.picture_at(entry, unquoted(rest)) or
                not_found
            headers Headers::MOCKUP
            content_type row[:type]
            row[:bytes].to_s
        end

        not_found { erb :not_found }
        error(422) { erb :unprocessable }
        error(500) { erb :failed }
        error(Ledger::Locked) { busy }
        error(Sequel::DatabaseError) do
            cause = env["sinatra.error"].wrapped_exception
            next busy if cause.is_a?(SQLite3::BusyException)

            status 500
            erb :failed
        end

        helpers do
            def busy
                status 503
                erb :busy
            end

            def page_headers
                content_type "text/html; charset=utf-8"
                headers Headers::PAGE
            end

            # The token the forms of this session's pages carry.
            def form_token
                held = sesam.session.held_from(request.env)
                FormToken.for(settings.config.session_secret, held)
            end

            # A name in a URL, unquoted:
            # Sinatra has decoded the percent escapes already, bytes that
            # are not UTF-8 become U+FFFD.
            def unquoted(name)
                name.dup.force_encoding(Encoding::UTF_8).scrub("\uFFFD")
            end

            # A browser navigating, not a program: it is sent to sign in
            # rather than handed a 401.
            # (An absent Accept is a program: Sinatra's accept? says yes.)
            def page?
                accept = request.env["HTTP_ACCEPT"].to_s
                request.get? && accept.include?("text/html")
            end

            def signed_out?
                sesam.access.caller_for(request.env).refused?
            end
        end
    end
end
