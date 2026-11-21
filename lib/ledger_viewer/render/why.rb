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

            # The paragraph a card or a line ends with.
            def link(lid, id)
                %(<p class="why"><a href="#{path(lid, id)}">) \
                    "Why #{id}, and what it led to</a></p>"
            end
        end
    end
end
