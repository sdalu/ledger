# frozen_string_literal: true

require "tilt"
require "erubi"

require_relative "helpers"
require_relative "icons"
require_relative "markup"
require_relative "terms"
require_relative "text"
require_relative "tips"

module LedgerViewer
    module Render
        # The ERB files of views/, rendered outside Sinatra: <%= %> is
        # escaped the way Python's html.escape does it (a quote is
        # &#x27;, a slash is left), <%== %> is for markup a helper built.
        # A fragment's source has its line breaks, and the indentation
        # after them, removed before it is compiled, because the Python
        # viewer's body is one line; a template that must keep its
        # newlines is rendered with `verbatim: true`.
        class Views
            OPTIONS = { escape: true, freeze_template_literals: false,
                        escapefunc: "::LedgerViewer::Render::Text.escape" }
                      .freeze
            BREAK = /\n[ \t]*/

            def initialize(dir)
                @dir = dir
                @cache = {}
                @lock = Mutex.new
            end

            def render(name, scope, locals = {}, verbatim: false)
                template(name, verbatim).render(scope, locals)
            end

            private

            def template(name, verbatim)
                @lock.synchronize do
                    @cache[[name, verbatim]] ||= compile(name, verbatim)
                end
            end

            def compile(name, verbatim)
                file = File.join(@dir, "#{name}.erb")
                source = File.read(file, encoding: "UTF-8")
                source = source.gsub(BREAK, "").chomp unless verbatim
                Tilt::ErubiTemplate.new(file, **OPTIONS) { source }
            end
        end

        # What a template calls: its partials and the helpers that build
        # markup from a ledger's text.
        class Scope
            # tips and titles: a ledger page's tooltips, and the titles of
            # its items, which an id link carries as a tip.
            def initialize(views, tips: nil, titles: {})
                @views = views
                @tips = tips
                @titles = titles
            end

            # A scope of its own for one page: its own tips, its titles.
            def page(titles) = Scope.new(@views, tips: Tips.new, titles:)

            def tip(text, hidden: false) = @tips.tip(text, hidden:)

            # A partial with its locals, as a Hash, as keywords, or both.
            def partial(name, locals = {}, **more)
                @views.render(name, self, locals.merge(more))
            end

            def chip(text, attrs = "") = Helpers.chip(text, attrs)

            def icon(name) = Icons.icon(name)

            def bar(done, total) = Helpers.bar(done, total)

            # A piece's awaited words as icons; the words themselves
            # follow them, for a screen reader only unless `visible`.
            def words_span(piece, visible: false)
                words = piece["words"]
                icons = words.map { icon(Terms::WORD_ICON.fetch(it.first)) }
                cls = visible ? "word" : "visually-hidden"
                %(<span class="words">#{icons.uniq.join}<span class="#{cls}">) +
                    "#{Text.escape(Terms.awaits_label(words))}</span></span>"
            end

            def inline(text)
                Markup.inline(text, @tips && [@tips, @titles])
            end

            def legend_ids = Helpers::LEGEND_IDS

            def legend_colours = Helpers::LEGEND_COLOURS
        end
    end
end
