# frozen_string_literal: true

require_relative "terms"
require_relative "text"

module LedgerViewer
    module Render
        # What ends a form of the inbox: the overall comment, the label
        # of the button that sends it, the link to the next question.
        # Mixed into SayForm, which holds the spec being drawn.
        module SayEnds
            OVERALL = "Add an overall comment"
            WHY = "Why (optional)"

            private

            def box
                what = @spec.order.empty? ? OVERALL : WHY
                @scope.partial(
                    "ledger/say_box",
                    { lid: @lid, fid: @fid, text: @prev["text"] || "", what:,
                      folded: folded? }
                )
            end

            def submit
                ref = @spec.ref
                case Terms.kind(ref)
                when "answer" then "#{verb} answer to #{ref}"
                when "comment" then "Send comment on #{ref}"
                when "order" then "Send this order"
                when "note" then "Send note"
                else "Send"
                end
            end

            def verb = @spec.replaces.empty? ? "Send" : "Replace"

            def after
                nxt = @spec.next_id
                return "" unless nxt

                %(<a class="next-question" href="#q-#{nxt}">) +
                    "Next: #{Text.escape(nxt)}</a>"
            end
        end
    end
end
