# frozen_string_literal: true

module LedgerViewer
    module Render
        # The way from a piece or a decision to its links page
        # (/l/LID/why/ID, LinksGraph): what led to it, what it led to.
        module Why
            # The ids that have a links page: a piece or a decision.
            STARTABLE = /\A[PX][1-9]\d*\z/

            module_function

            def path(lid, id) = "/l/#{lid}/why/#{id}"

            # The icon beside an id chip that leads to its links page, the
            # sentence it stands for as its title and accessible name.
            def icon(lid, id)
                said = "Why #{id}, and what it led to"
                %(<a class="why-icon" href="#{path(lid, id)}" ) +
                    %(title="#{said}" aria-label="#{said}">) +
                    "#{Icons.icon("route")}</a>"
            end
        end
    end
end
