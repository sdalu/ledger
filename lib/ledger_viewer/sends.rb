# frozen_string_literal: true

require "json"

module LedgerViewer
    # What the page's script talks to: the sends it posts (a form, one
    # word for several pieces, the tray), the stamp it polls and the
    # stream that pushes the stamp when it moves. A Sinatra extension,
    # registered on Web.
    module Sends
        ROUTE = %r{/l/([0-9a-f]{10})/(say|say-all|say-batch)}

        def self.registered(app)
            app.helpers SendHelpers
            app.post(ROUTE) do |lid, route|
                redirect to(file(lid, route), false), 303
            end
            app.get("/stamp") { stamp_page }
            app.get("/events") { stamp_stream }
            app.error(Refusal) { refused(env["sinatra.error"]) }
        end

        # What the routes use.
        module SendHelpers
            # A send, from a session that holds the token of its forms:
            # into the ledger's inbox, and where the page goes back to.
            def file(lid, route)
                own_origin!
                length = content_length
                post = Sender::Post.new(
                    lid:, route:, length:, action: request.path_info,
                    body: raw_body(length), token: form_token!, actor:
                )
                settings.sender.call(post)
            end

            # The stamp the page was drawn with, asked again by the
            # page's fallback poll: with `lid`, that ledger's alone.
            def stamp_page
                page_headers
                content_type "text/plain; charset=utf-8"
                current_stamp(query.get("lid"))
            end

            # `since` is the stamp of the page asking, or the current one;
            # `lid` the ledger whose page asks, whose stamp moves with that
            # ledger alone.
            def stamp_stream
                lid = query.get("lid")
                since = query.get("since")
                headers Headers::EVENTS
                response["Content-Type"] = "text/event-stream"
                Events.new(since || current_stamp(lid),
                           -> { current_stamp(lid) },
                           socket: request.env["puma.socket"])
            end

            def refusal_page(refused)
                page_headers
                status refused.status
                settings.renderer.refusal(refused.message, stale_page(refused))
            end

            # A refused send: the tray's in JSON, any other a page.
            def refused(refusal)
                tray? ? tray_refusal(refusal) : refusal_page(refusal)
            end

            # The tray's refusal, for its page's script: why, and each
            # item refused with its status and why (Tray::Refused).
            def tray_refusal(refused)
                page_headers
                status refused.status
                content_type "application/json; charset=utf-8"
                items = refused.respond_to?(:items) ? refused.items : []
                JSON.generate(why: refused.message, items:)
            end

            private

            def tray? = request.path_info.end_with?("/say-batch")

            # A form posted by a page of this viewer: its Origin is the
            # scheme (rack.url_scheme, which Puma sets to https under TLS)
            # and host the request itself came to. No Origin is refused
            # too: a browser always sends one with a form.
            def own_origin!
                host = request.env["HTTP_HOST"].to_s
                return if !host.empty? &&
                          request.env["HTTP_ORIGIN"] ==
                          "#{request.scheme}://#{host}"

                raise Refusal.new(403, "The form did not come from this " \
                                       "viewer's own page.")
            end

            def lan_caller? = caller_now.verdict == :lan

            def caller_now = sesam.access.caller_for(request.env)

            # Who the journal's events row names: the signed-in user, or
            # the name sesam gives a LAN caller (its user, or lan:ADDRESS).
            def actor
                held = sesam.session&.held_from(request.env)
                "viewer:#{held ? held.name : caller_now.name}"
            end

            def query = @query ||= Form.parse(request.query_string)

            # Every live ledger's stamp, or with `lid` that ledger's.
            def current_stamp(lid = nil)
                entries = settings.ledgers.all
                return Render::Stamp.of(entries) unless lid

                Render::Stamp.ledger(entries, lid)
            end

            # The token a send must carry: a caller with no session has a
            # form to send from only on the LAN (its token is the one the
            # pages give a caller without a session); a key has none.
            def form_token!
                held = sesam.session&.held_from(request.env)
                unless held || lan_caller?
                    raise Refusal.new(403, "Sending needs a signed-in session.")
                end

                FormToken.for(settings.config.session_secret, held)
            end

            # The first `length` bytes of the body, which Sinatra has read
            # once already to make its params.
            def raw_body(length)
                request.body.rewind
                request.body.read([length, 0].max).to_s
            end

            # The Content-Length as an integer, -1 when it
            # is not a number.
            def content_length
                text = request.env["CONTENT_LENGTH"] || "0"
                text.match?(/\A\s*[+-]?\d+\s*\z/) ? text.to_i : -1
            end

            # What the refusal page of a stale form carries, or nil.
            def stale_page(refused)
                return unless refused.is_a?(Stale)

                { action: refused.action, token: form_token,
                  fields: refused.fields, text: refused.text }
            end
        end
    end
end
