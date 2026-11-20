# frozen_string_literal: true

require_relative "index"
require_relative "notices"
require_relative "ledger_page"
require_relative "page"
require_relative "stamp"
require_relative "views"
require_relative "../dump"

module LedgerViewer
    module Render
        # The pages, built from a Config: what a route or the comparison
        # harness calls. No Sinatra in it.
        class Renderer
            VIEWS = File.expand_path("../../../views", __dir__)

            def initialize(config, views_dir: VIEWS)
                views = Views.new(views_dir)
                scope = Scope.new(views)
                page = Page.new(views, scope, config.stylesheet)
                @index = Index.new(views, scope, page)
                @ledger = LedgerPage.new(scope, page)
                @page = page
                @dump = Dump.new(python: config.python,
                                 script: config.ledger_py,
                                 timeout: config.dump_timeout)
            end

            # The page of the ledger `entry`, a member of `entries` (the
            # stamp is every ledger's), for the form token `token`.
            def ledger(entries, entry, token)
                data = @dump.read(entry.path)
                stamp = Stamp.of(entries)
                return unreadable(entry, stamp) unless data

                @ledger.html(entry, data, stamp, token)
            end

            # The same page from its start to where the section of
            # unfinished pieces opens (the whole page of an unreadable
            # ledger).
            def ledger_top(entries, entry, token)
                data = @dump.read(entry.path)
                stamp = Stamp.of(entries)
                return unreadable(entry, stamp) unless data

                @ledger.top(entry, data, stamp, token)
            end

            # The index page for these ledger entries, each read on a
            # thread of its own.
            def index(entries)
                readings = entries.map do |entry|
                    Thread.new { [entry.path, @dump.read(entry.path)] }
                end.to_h(&:value)
                @index.html(entries, readings, Stamp.of(entries))
            end

            # A ledger as the engine reads it, or nil.
            def read(path) = @dump.read(path)

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

            def unreadable(entry, stamp)
                body = LedgerPage::CRUMBS +
                       "<h1>#{Text.escape(entry.path)}</h1>" \
                       "<p>Cannot be read.</p>"
                @page.html(title: "Ledger", body:, stamp:)
            end
        end
    end
end
