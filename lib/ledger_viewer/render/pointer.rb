# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # A fact's pointer or a constraint's where, drawn by the kind the
        # JSON document gives it (docs/journal.md, section 6): a URL as a
        # link opening a new tab, a path in monospace, a turn as written
        # and titled; free text, or no kind, returns nil and is drawn as
        # any line is.
        module Pointer
            TURN = "said in the conversation"

            module_function

            def html(text, kind)
                safe = Text.escape(text)
                case kind
                when "url"
                    %(<a href="#{safe}" rel="noopener" target="_blank">) +
                        "#{safe}</a>"
                when "path" then %(<code title="file">#{safe}</code>)
                when "turn" then %(<span title="#{TURN}">#{safe}</span>)
                end
            end
        end
    end
end
