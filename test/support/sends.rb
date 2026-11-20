# frozen_string_literal: true

# What the tests of the sends share: the ledger's inbox, the token of
# its page's forms, and a send as the page's form makes it.
module Sends
    def inbox = "#{@ledger}.inbox"

    def lines = File.exist?(inbox) ? File.readlines(inbox, chomp: true) : []

    def token
        https "/l/#{@lid}"
        last_response.body[/name="token" value="([^"]*)"/, 1]
    end

    # The headers of a form a page of this viewer posts.
    def form
        { "CONTENT_TYPE" => "application/x-www-form-urlencoded",
          "HTTP_ORIGIN" => "https://localhost" }
    end

    def say(pairs, route: "say", token: token(), headers: {})
        body = URI.encode_www_form([["token", token], *pairs])
        https("/l/#{@lid}/#{route}", :post, body, form.merge(headers))
    end
end
