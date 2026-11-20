# frozen_string_literal: true

module LedgerViewer
    module Render
        # The page around a body, as ledger-serve.py's page() writes it
        # with the viewer script on and no MathJax: the stylesheet and the
        # script inline, read as the Python viewer's own files, the
        # script's icon slots filled.
        class Page
            SLOTS = { "__ICON_X__" => "x",
                      "__ICON_MAXIMIZE__" => "maximize-2",
                      "__ICON_REFRESH__" => "refresh-cw" }.freeze

            def initialize(views, scope, stylesheet)
                @views = views
                @scope = scope
                @css = File.read(stylesheet, encoding: "UTF-8")
                @js = script(File.join(File.dirname(stylesheet), "viewer.js"))
            end

            # skip: the link past the page's head to what waits; ledger:
            # the page is a ledger's, which the script and the style
            # address.
            def html(title:, body:, stamp:, skip: false, ledger: false)
                render(title:, body:, stamp:, skip:, ledger:, live: true)
            end

            # A page that only says something (why a send was not
            # taken): no stamp, and the script left out.
            def notice(title:, body:)
                render(title:, body:, stamp: "", skip: false, ledger: false,
                       live: false)
            end

            private

            def render(**locals)
                @views.render("shared/page", @scope,
                              locals.merge(css: @css, js: @js),
                              verbatim: true)
            end

            def script(file)
                source = File.read(file, encoding: "UTF-8")
                SLOTS.reduce(source) do |text, (slot, name)|
                    text.gsub(slot, Icons.icon(name))
                end
            end
        end
    end
end
