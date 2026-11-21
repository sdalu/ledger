# frozen_string_literal: true

require_relative "../links_graph"
require_relative "helpers"
require_relative "index"
require_relative "notices"
require_relative "ledger_page"
require_relative "page"
require_relative "stamp"
require_relative "views"
require_relative "why"

module LedgerViewer
    module Render
        # The pages, built from a Config and the journal's Ledgers: what
        # a route calls. No Sinatra in it.
        class Renderer
            VIEWS = File.expand_path("../../../views", __dir__)

            def initialize(config, ledgers, views_dir: VIEWS)
                views = Views.new(views_dir)
                scope = Scope.new(views)
                page = Page.new(views, scope, config.stylesheet, config.script)
                @index = Index.new(views, scope, page)
                @ledger = LedgerPage.new(scope, page, ledgers)
                @page = page
                @ledgers = ledgers
                @views = views
                @scope = scope
                @links_css = File.read(links_css(config), encoding: "UTF-8")
            end

            # The page of the ledger `entry` (Ledgers::Entry), for the
            # form token `token`.
            def ledger(entry, token)
                entries = @ledgers.all
                @ledger.html(entry, @ledgers.read(entry), Stamp.of(entries),
                             token)
            end

            # The index page: every live ledger's document.
            def index
                entries = @ledgers.all
                readings = entries.to_h { [it.id, @ledgers.read(it)] }
                @index.html(entries, readings, Stamp.of(entries))
            end

            # The links page of piece or decision `id` of the ledger
            # `entry`: what led to it, what it led to (LinksGraph). Raises
            # LinksGraph::Error when the ledger has no such item.
            def links(entry, id)
                view = LinksGraph.call(@ledgers.read(entry), id)
                href = lambda do |to|
                    Why.path(entry.id, to) if Why::STARTABLE.match?(to)
                end
                body = @views.render("ledger/links", @scope, { view:, href: })
                name = Helpers.project_name(entry.project, entry.path)
                @page.html(title: "Why #{id} — #{name}", body:,
                           stamp: Stamp.of(@ledgers.all),
                           styles: [@links_css])
            end

            # The page that says a send was refused, or was not taken
            # because its token was not this session's (`stale`: the
            # keywords of Notices.stale).
            def refusal(why, stale = nil)
                body = if stale
                           Notices.stale(**stale)
                       else
                           Notices.refused(why)
                       end
                title = stale ? "Not sent yet" : "Not sent"
                @page.notice(title:, body:)
            end

            private

            # public/links.css, beside the viewer's stylesheet.
            def links_css(config)
                File.join(File.dirname(config.stylesheet), "links.css")
            end
        end
    end
end
