# frozen_string_literal: true

require "sinatra/base"
require "sesam/sinatra"

module LedgerViewer
    # The viewer: /health open to anyone, the sign-in and invitation
    # pages, sesam's JSON routes, and behind the gate the index of live
    # ledgers, a ledger's page and its pictures, drawn by Render. Pages
    # and pictures carry the Python viewer's headers (Headers). Errors
    # are answers: show_exceptions and raise_errors are off, and 404 and
    # 422 have pages.
    class Web < Sinatra::Base
        # Reachable without being admitted: the monitor's route, the two
        # pages a browser signs in through, and the stylesheet they use
        # (public/ is served before any filter, scripts included).
        PUBLIC = %w[/health /sign-in /invite /viewer.css].freeze

        register Sesam::Sinatra
        register Sends

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

        # The app for `config`, a subclass of its own so that two builds
        # (two tests) never share settings.
        def self.configured(config, db: Accounts.open(config))
            renderer = Render::Renderer.new(config)
            Class.new(self) do
                ledgers = Ledgers.new(config.roots)
                set config:, renderer:, ledgers:,
                    sender: Sender.new(ledgers, renderer),
                    sesam: Accounts.settings(config, db)
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

        get "/viewer.css" do
            content_type :css
            File.read(settings.config.stylesheet)
        end

        get "/" do
            page_headers
            settings.renderer.index(settings.ledgers.all)
        end

        get %r{/l/([0-9a-f]{10})} do |lid|
            entries = settings.ledgers.all
            entry = entries.find { it.id == lid } or not_found
            page_headers
            settings.renderer.ledger(entries, entry, form_token)
        end

        # A ledger's pictures: its own files and nothing outside.
        get %r{/m/([0-9a-f]{10})/(.+)} do |lid, name|
            entry = settings.ledgers.all.find { it.id == lid }
            real = entry && Render::Folder.file(entry.mockups, unquoted(name))
            not_found unless real
            headers Headers::MOCKUP
            content_type Render::Terms::MOCKUP_TYPES
                .fetch(Render::Terms.ext(real).downcase)
            File.binread(real)
        end

        not_found { erb :not_found }
        error(422) { erb :unprocessable }
        error(500) { erb :failed }

        helpers do
            def page_headers
                content_type "text/html; charset=utf-8"
                headers Headers::PAGE
            end

            # The token the forms of this session's pages carry.
            def form_token
                held = sesam.session.held_from(request.env)
                FormToken.for(settings.config.session_secret, held)
            end

            # A name in a URL as Python's urllib.parse.unquote reads it:
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
