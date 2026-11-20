# frozen_string_literal: true

module LedgerViewer
    # What the page's script talks to: the sends it posts, the stamp it
    # polls and the stream that pushes the stamp when it moves. A Sinatra
    # extension, registered on Web.
    module Sends
        def self.registered(app)
            app.helpers SendHelpers
            app.post(%r{/l/([0-9a-f]{10})/(say|say-all)}) do |lid, route|
                redirect to(file(lid, route), false), 303
            end
            app.get("/stamp") { stamp_page }
            app.get("/events") { stamp_stream }
            app.error(Refusal) { refusal_page(env["sinatra.error"]) }
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
                    body: raw_body(length), token: form_token!
                )
                settings.sender.call(post)
            end

            # The stamp the page was drawn with, asked again by the
            # page's fallback poll.
            def stamp_page
                page_headers
                content_type "text/plain; charset=utf-8"
                current_stamp
            end

            # `since` is the stamp of the page asking, or the current one.
            def stamp_stream
                since = Form.parse(request.query_string).get("since")
                headers Headers::EVENTS
                response["Content-Type"] = "text/event-stream"
                Events.new(since || current_stamp, -> { current_stamp },
                           socket: request.env["puma.socket"])
            end

            def refusal_page(refused)
                page_headers
                status refused.status
                settings.renderer.refusal(refused.message, stale_page(refused))
            end

            private

            # A form posted by a page of this viewer: its Origin is the
            # scheme and host the request itself came to, as ledger-
            # serve.py's do_POST asks. No Origin is refused too: a
            # browser always sends one with a form.
            def own_origin!
                scheme = request.env["HTTPS"] == "on" ? "https" : "http"
                host = request.env["HTTP_HOST"].to_s
                return if !host.empty? &&
                          request.env["HTTP_ORIGIN"] == "#{scheme}://#{host}"

                raise Refusal.new(403, "The form did not come from this " \
                                       "viewer's own page.")
            end

            def lan_caller?
                sesam.access.caller_for(request.env).verdict == :lan
            end

            def current_stamp = Render::Stamp.of(settings.ledgers.all)

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

            # The Content-Length as Python's int() reads it, -1 when it
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
