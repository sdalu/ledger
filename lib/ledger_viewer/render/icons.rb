# frozen_string_literal: true

require "json"

module LedgerViewer
    module Render
        # The viewer's inline icons, drawn as viewer_icons.py's icon()
        # draws them. icons.json holds that module's two tables, dumped
        # as they are (json.dump of {"lucide": LUCIDE, "git": GIT}); a
        # test compares every icon with the Python's.
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
