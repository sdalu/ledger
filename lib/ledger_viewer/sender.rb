# frozen_string_literal: true

require "ledger"
require "ledger/inbox"

require_relative "form"
require_relative "render/next_waiting"
require_relative "render/reading"
require_relative "say"

module LedgerViewer
    # A form posted to a ledger, taken in its order: the size, the token,
    # the ledger, the reading of it, the rules of Say, then the entries
    # filed by Ledger::Inbox.append, actor `viewer:<caller>`. The reading,
    # the rules and the append are one write transaction, so the inbox a
    # send checks (what it replaces) is the inbox it is filed into.
    # Returns where the page goes back to, or raises the Refusal.
    class Sender
        MAX_BODY = 64 * 1024

        # What was posted: to ledger `lid`, `route` (say or say-all), a
        # `body` of `length` bytes (the Content-Length, -1 when it is no
        # number), `action` the path posted to, `token` the one this
        # session's forms carry, `actor` who sent it (the events row's).
        Post = Data.define(:lid, :route, :body, :length, :action, :token,
                           :actor)

        def initialize(ledgers) = @ledgers = ledgers

        def call(post)
            refuse(413, "Empty or too long.") unless
                post.length.between?(1, MAX_BODY)
            form = Form.parse(post.body)
            stale!(form, post)
            @ledgers.journal.transaction { file(form, post) }
        rescue Ledger::Locked
            raise
        rescue Ledger::Refused => e
            refuse(409, "#{e.message}; nothing was sent.")
        end

        private

        def file(form, post)
            entry = ledger(post.lid)
            bodies = bodies(Say.new(@ledgers.read(entry), form), post.route)
            Ledger::Inbox.append(@ledgers.journal, entry.path,
                                 bodies.map { entry_of(it) },
                                 actor: post.actor)
            "/l/#{post.lid}##{anchor(entry, post.route, bodies.first)}"
        end

        # The hash Inbox.append files: the fields, then the text.
        def entry_of(body) = body.fields.merge("text" => body.text)

        # The card acted on; an answer or a word turns its card into a
        # receipt, so the page moves on to the first card still waiting,
        # the one acted on when none does.
        def anchor(entry, route, body)
            return body.anchor unless route == "say" && receipt?(body)

            reading = Render::Reading.new(@ledgers.read(entry))
            first = Render::NextWaiting.cards(reading).first
            first ? first[0] : body.anchor
        end

        # A comment on a question leaves its card as it was.
        def receipt?(body)
            return false if body.fields["comment"]

            body.anchor.start_with?("q-") ||
                (body.anchor.start_with?("p-") &&
                    !body.fields.fetch("word", "").empty?)
        end

        def bodies(say, route) = route == "say-all" ? say.all : say.one

        def ledger(lid)
            @ledgers.find(lid) or refuse(404, "No live ledger by that name.")
        end

        def refuse(status, why) = raise(Refusal.new(status, why))

        def stale!(form, post)
            return if Rack::Utils.secure_compare(form["token"], post.token)

            raise Stale.new(form.fields.except("token", "text"), form["text"],
                            post.action)
        end
    end
end
