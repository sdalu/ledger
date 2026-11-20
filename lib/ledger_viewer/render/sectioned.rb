# frozen_string_literal: true

require_relative "terms"

module LedgerViewer
    module Render
        # section() of ledger-serve.py: a heading with its icon and
        # count, and the list under it. Mixed into what holds @scope.
        module Sectioned
            private

            # A section's heading and its list; `empty` is said when
            # the list is empty, and a section with neither says nothing.
            def section(title, entries, anchor, empty: nil)
                icon = @scope.icon(Terms::SECTION_ICON[anchor])
                head = %(<h2 id="#{anchor}">#{icon}#{title} ) +
                       %(<span class="count">#{entries.length}</span></h2>)
                return "#{head}<p>#{empty}</p>" if entries.empty? && empty
                return "" if entries.empty?

                %(#{head}<ul class="entries">#{entries.join}</ul>)
            end
        end
    end
end
