# frozen_string_literal: true

require_relative "age"

module LedgerViewer
    module Render
        # The page around a body, with the viewer script on and no
        # MathJax: the stylesheet and the script of public/ inline (the
        # page's policy allows inline style and script only), the
        # script's icon slots filled.
        class Page
            SLOTS = { "__ICON_X__" => "x",
                      "__ICON_MAXIMIZE__" => "maximize-2" }.freeze
            LOOK = { skip: false, ledger: false, index: false, links: false,
                     styles: [].freeze }.freeze

            def initialize(views, scope, stylesheet, javascript)
                @views = views
                @scope = scope
                @css = File.read(stylesheet, encoding: "UTF-8")
                @js = script(javascript)
            end

            # How a page looks beyond its body (LOOK): skip, the link past
            # the page's head to what waits; ledger, the page is a
            # ledger's, which the script and the style address; index,
            # the page is the index, whose rows the script swaps; links,
            # the page is a piece's links page, whose parts the script
            # swaps; styles, more stylesheets' text, after the viewer's.
            def html(title:, body:, stamp:, **look)
                unknown = look.keys - LOOK.keys
                raise ArgumentError, "unknown: #{unknown}" if unknown.any?

                render(title:, body:, stamp:, **LOOK, **look, live: true)
            end

            # A page that only says something (why a send was not
            # taken): no stamp, and the script left out.
            def notice(title:, body:)
                render(title:, body:, stamp: "", **LOOK, live: false)
            end

            private

            # The ages the body's helpers bracketed (Age) become elements
            # the script can find; the title holds no markup.
            def render(title:, body:, **locals)
                @views.render("shared/page", @scope,
                              locals.merge(title: Age.strip(title),
                                           body: Age.mark(body),
                                           css: @css, js: @js),
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
