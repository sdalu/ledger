# frozen_string_literal: true

# What the tests of the sends share: the ledger's inbox in the journal,
# the token of its page's forms, and a send as the page's form makes it.
module Sends
    # The ledger's inbox entries, oldest first, each the hash
    # Ledger::Inbox filed: id, at, the form's fields, text.
    def entries
        inbox_rows.map { JSON.parse(it[:payload]) }
    end

    # The actor of the event that filed each entry, oldest first.
    def actors
        db = @journal.db
        inbox_rows.map do |row|
            filed = db[:event_rows].where(tbl: "inbox_entries",
                                          row_id: row[:id])
            db[:events].where(id: filed.select(:event_id)).get(:actor)
        end
    end

    def inbox_rows
        ledger = @journal.ledger(@ledger)
        @journal.db[:inbox_entries].where(ledger_id: ledger[:id]).order(:n).all
    end

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
