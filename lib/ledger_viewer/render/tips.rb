# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # The tooltips of one page: each pairs an anchor with a tip by a
        # name of its own, so no two on a page collide. tip() of
        # ledger-serve.py, with its counter per page, not per process.
        class Tips
            def initialize = @count = 0

            # [the anchor's attributes, the tip that must follows it];
            # `hidden` when the anchor's own label already says it.
            def tip(text, hidden: false)
                name = "tip-#{@count += 1}"
                [anchor(name, hidden), box(name, text, hidden)]
            end

            private

            def anchor(name, hidden)
                %( style="anchor-name: --#{name}") +
                    (hidden ? "" : %( aria-describedby="#{name}"))
            end

            def box(name, text, hidden)
                %(<span class="tip" role="tooltip" id="#{name}" ) +
                    %(style="position-anchor: --#{name}") +
                    (hidden ? ' aria-hidden="true"' : "") +
                    ">#{Text.escape(text)}</span>"
            end
        end
    end
end
