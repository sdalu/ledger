# frozen_string_literal: true

require_relative "form"
require_relative "inbox"
require_relative "render/next_waiting"
require_relative "render/reading"
require_relative "say"

module LedgerViewer
    # A form posted to a ledger, taken as ledger-serve.py's do_POST takes
    # it, in its order: the size, the token, the ledger, the reading of
    # it, the rules of Say, then the append. Returns where the page goes
    # back to, or raises the Refusal.
    class Sender
        MAX_BODY = 64 * 1024

        # What was posted: to ledger `lid`, `route` (say or say-all), a
        # `body` of `length` bytes (the Content-Length, -1 when it is no
        # number), `action` the path posted to, `token` the one this
        # session's forms carry.
        Post = Data.define(:lid, :route, :body, :length, :action, :token)

        # `reader` answers a ledger's dump (a Hash, or nil) for a path.
        def initialize(ledgers, reader)
            @ledgers = ledgers
            @reader = reader
        end

        def call(post)
            refuse(413, "Empty or too long.") unless
                post.length.between?(1, MAX_BODY)
            form = Form.parse(post.body)
            stale!(form, post)
            path, data = ledger(post.lid)
            bodies = bodies(Say.new(data, form), post.route)
            Inbox.append(path, bodies)
            "/l/#{post.lid}##{anchor(path, post.route, bodies.first)}"
        end

        private

        # The card acted on; an answer or a word turns its card into a
        # receipt, so the page moves on to the first card still waiting,
        # the one acted on when none does.
        def anchor(path, route, body)
            return body.anchor unless route == "say" && receipt?(body)

            after = @reader.read(path)
            first = after && Render::NextWaiting.cards(Render::Reading.new(after)).first
            first ? first[0] : body.anchor
        end

        def receipt?(body)
            body.anchor.start_with?("q-") ||
                (body.anchor.start_with?("p-") &&
                    !body.fields.fetch("word", "").empty?)
        end

        def bodies(say, route) = route == "say-all" ? say.all : say.one

        # The path of the live ledger `lid` and what the engine reads of it.
        def ledger(lid)
            entry = @ledgers.all.find { it.id == lid } or
                refuse(404, "No live ledger by that name.")
            data = @reader.read(entry.path) or
                refuse(409, "The ledger cannot be read.")
            [entry.path, data]
        end

        def refuse(status, why) = raise(Refusal.new(status, why))

        def stale!(form, post)
            return if Rack::Utils.secure_compare(form["token"], post.token)

            raise Stale.new(form.fields.except("token", "text"), form["text"],
                            post.action)
        end
    end
end
