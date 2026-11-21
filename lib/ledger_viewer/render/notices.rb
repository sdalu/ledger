# frozen_string_literal: true

require_relative "icons"
require_relative "text"

module LedgerViewer
    module Render
        # The pages that answer a send that is not taken, as a refusal
        # and a stale page write them: bodies only,
        # for Page to put in its frame.
        module Notices
            CRUMBS = '<p class="crumbs"><a href="/">All ledgers</a></p>'
            MAX_TEXT = 4000

            module_function

            def refused(why)
                "#{CRUMBS}<h1>Not sent</h1><p>#{Text.escape(why)}</p>"
            end

            # The form sent again on one click: what was typed, under
            # this server's token.
            def stale(action:, token:, fields:, text:)
                "#{CRUMBS}<h1>Not sent yet</h1>#{STALE_WORDS}" \
                    "<form class=\"say\" method=\"post\" " \
                    "action=\"#{Text.escape(action)}\">" \
                    "<input type=\"hidden\" name=\"token\" " \
                    "value=\"#{token}\">#{hidden(fields)}" \
                    "<textarea name=\"text\" maxlength=\"#{MAX_TEXT}\" " \
                    "aria-label=\"Your text\">#{Text.escape(text)}" \
                    "</textarea><div class=\"actions\"><button " \
                    "type=\"submit\">#{Icons.icon("send")}Send again" \
                    "</button></div></form>"
            end

            STALE_WORDS = "<p>The viewer restarted after this page was " \
                          "opened, so the send was refused. Nothing is " \
                          "lost: what you sent is below. Check it, then " \
                          "send it again.</p>"

            def hidden_input(name, value)
                "<input type=\"hidden\" name=\"#{Text.escape(name)}\" " \
                    "value=\"#{Text.escape(value)}\">"
            end

            def hidden(fields)
                fields.flat_map do |name, values|
                    values.map { |value| hidden_input(name, value) }
                end.join
            end
        end
    end
end
