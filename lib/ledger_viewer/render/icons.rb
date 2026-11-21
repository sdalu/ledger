# frozen_string_literal: true

require "json"

module LedgerViewer
    module Render
        # The viewer's inline icons. icons.json holds the two tables, as
        # {"lucide": {name => inner SVG}, "git": inner SVG}; a test pins
        # the SVG each name draws by its digest.
        module Icons
            TABLE = JSON.parse(File.read(File.join(__dir__, "icons.json")))
                        .freeze
            STROKE = 'fill="none" stroke="currentColor" stroke-width="2" ' \
                     'stroke-linecap="round" stroke-linejoin="round"'
            FILL = 'fill="currentColor"'

            def self.names = TABLE["lucide"].keys + ["git"]

            def self.icon(name, cls = "icon")
                inner, paint = shape(name)
                %(<svg class="#{cls}" viewBox="0 0 24 24" #{paint} ) +
                    %(aria-hidden="true" focusable="false">#{inner}</svg>)
            end

            def self.shape(name)
                return [TABLE["git"], FILL] if name == "git"

                [TABLE["lucide"].fetch(name), STROKE]
            end
        end
    end
end
