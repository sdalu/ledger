# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # The Remains section of a ledger with every criterion marked, no
        # piece in flight and no question open: Ready when the status
        # line proposes the close, else what still holds it, as the
        # status line says it.
        module Remains
            HEAD = '<h2 id="waiting">Remains</h2>'
            READY = "#{HEAD}<p>Nothing: every criterion marked, no piece " \
                    "in flight, no question open. Ready for " \
                    "<code>bin/ledger close</code>.</p>".freeze
            VIEWER = "from the viewer: "
            # The close held with nothing the status line names: a
            # --final rule still fails.
            FINAL = "<code>bin/ledger check --final</code> still fails"

            module_function

            def html(reading)
                return READY if reading.ready_to_close?

                "#{HEAD}<p>Not yet: #{holds(reading.status)}.</p>"
            end

            def holds(status)
                ids = viewer(status)
                return FINAL if ids.empty?

                refs = Text.escape(ids.join(", "))
                if ids.length == 1
                    "an entry from you waits to be filed (#{refs})"
                else
                    "entries from you wait to be filed (#{refs})"
                end
            end

            # The entries sent and not filed, as the status line names
            # them.
            def viewer(status)
                part = status.split(" · ").find { it.start_with?(VIEWER) }
                part ? part.delete_prefix(VIEWER).split(", ") : []
            end
        end
    end
end
