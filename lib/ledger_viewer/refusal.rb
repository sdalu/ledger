# frozen_string_literal: true

module LedgerViewer
    # A send that is refused, with the status it is refused by and the
    # sentence the page says; nothing is written.
    class Refusal < Error
        attr_reader :status

        def initialize(status, why)
            super(why)
            @status = status
        end
    end

    # A send whose token is not the session's: the page of an earlier
    # run of the server. Carries the form back, so that what was typed is
    # shown and sent again on one click.
    class Stale < Refusal
        attr_reader :fields, :text, :action

        def initialize(fields, text, action)
            super(403, "The form is from an earlier page of this viewer.")
            @fields = fields
            @text = text
            @action = action
        end
    end
end
