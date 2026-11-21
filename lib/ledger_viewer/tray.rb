# frozen_string_literal: true

require "json"

require_relative "form"
require_relative "refusal"
require_relative "say"

module LedgerViewer
    # The tray the page collected, sent in one request: `items`, a JSON
    # list of the forms trayed, each {name => value} as its single send
    # would have posted it. Each item is checked by Say as that send
    # would be, in the tray's order, seeing the items before it as sent
    # and not filed; the entries, one per item, or the Refused that
    # names every item refused, and nothing is filed.
    class Tray
        # Every item refused, each {item (its index), ref, status, why}.
        # The status is 400 when any item's is, else 409.
        class Refused < Refusal
            attr_reader :items

            def initialize(items)
                super(items.any? { it[:status] == 400 } ? 400 : 409,
                      "Nothing was sent: the tray holds items refused.")
                @items = items
            end
        end

        def initialize(data, form)
            @data = data
            @items = items(form["items"])
        end

        def bodies
            refused = []
            accepted = []
            @items.each_with_index do |fields, at|
                accepted << [at, check(fields, accepted)]
            rescue Refusal => e
                refused << { item: at, ref: fields["ref"]&.first,
                             status: e.status, why: e.message }
            end
            raise Refused, refused unless refused.empty?

            accepted.map(&:last)
        end

        private

        def check(fields, before)
            Say.new(seen(before), Form.new(fields)).trayed.first
        end

        def items(text)
            list = JSON.parse(text)
            raise TypeError unless list.is_a?(Array) && !list.empty?

            list.map { fields(it) }
        rescue JSON::ParserError, TypeError
            raise Refusal.new(400, "The tray sent no list of items.")
        end

        # One item's form, its token left out: the request's is checked.
        def fields(item)
            raise TypeError unless item.is_a?(Hash) &&
                                   item.all? { |k, v| [k, v].all?(String) }

            item.except("token").transform_values { [it] }
        end

        # The ledger as an item reads it: the items accepted before it
        # among its inbox's entries, sent and not filed.
        def seen(before)
            rows = before.map { |at, body| row(at, body) }
            @data.merge("inbox" => @data["inbox"] + rows)
        end

        def row(at, body)
            payload = JSON.generate(body.fields.merge("text" => body.text))
            { "id" => "tray item #{at + 1}", "taken" => false,
              "malformed" => false, "payload" => payload }
        end
    end
end
