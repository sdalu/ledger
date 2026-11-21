# frozen_string_literal: true

module LedgerViewer
    # The waker's switch on a ledger page: POST /l/ID/waker, `waker` on
    # or off, from a page of this viewer carrying its session's token,
    # written as the `waker` command writes it (one event, actor
    # `viewer:<caller>`); the page goes back to the switch. A Sinatra
    # extension, registered on Web after Sends, whose helpers it uses.
    module WakerSwitch
        MAX_BODY = 1024
        WORDS = { "on" => true, "off" => false }.freeze

        def self.registered(app)
            app.helpers Helpers
            app.post(%r{/l/([0-9a-f]{10})/waker}) do |lid|
                redirect to(switch_waker(lid), false), 303
            end
        end

        # What the route uses.
        module Helpers
            def switch_waker(lid)
                own_origin!
                form = waker_form
                on = WORDS.fetch(form["waker"]) do
                    raise Refusal.new(400, "The waker is switched on or off.")
                end
                entry = settings.ledgers.find(lid) or
                    raise Refusal.new(404, "No live ledger by that name.")
                settings.ledgers.switch_waker(entry, on, actor:)
                "/l/#{lid}#waker"
            end

            private

            # The posted form, refused when empty, too long, or not carrying
            # the token of this session's pages.
            def waker_form
                length = content_length
                raise Refusal.new(413, "Empty or too long.") unless
                    length.between?(1, MAX_BODY)

                form = Form.parse(raw_body(length))
                return form if
                    Rack::Utils.secure_compare(form["token"], form_token!)

                raise Refusal.new(409, "This page is out of date: reload " \
                                       "it, then switch again.")
            end
        end
    end
end
