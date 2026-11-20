# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # The small Markdown a ledger line uses, drawn as inline() draws
        # it: escaped first, then code spans, links, bold and italics;
        # nothing else is trusted. Code and maths are set aside first so
        # that a `*` inside them is never read as emphasis. A link whose
        # text is only an item id, on a page that holds titles, carries
        # the item's title as a tip.
        module Markup
            CODE = /`([^`]+)`/
            URL = %r{(?u)https?://[^\s<>"')]+}
            LINK = %r{(?u)\[([^\]\n]+)\]\((https?://[^\s)]+|#[A-Za-z][\w-]*)\)}
            STRONG = /(?u)(?<![\w*])\*\*(?=\S)(.+?)(?<=\S)\*\*(?![\w*])/
            EM = /(?u)(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])|
                  (?<![\w_])_(?=\S)(.+?)(?<=\S)_(?![\w_])/x
            MATH = /(?u)(?<![\\$\w])\$(?=\S)[^$\n]+?(?<=\S)\$(?![\w$])/
            HOLE = /\x00(\d+)\x00/
            ID_HREF = /\A#(?:piece|p|q|crit)-([A-Z]\d+)\z/
            BARE_ID = /\A[A-Z]\d+\z/
            TIP_MAX = 90
            # What is set aside, in order, and what stands for it.
            SHIELDED = [
                [CODE, ->(m, _) { "<code>#{m[1]}</code>" }],
                [MATH, ->(m, _) { m[0] }],
                [LINK, ->(m, tips) { link(m[1], m[2], tips) }],
                [URL, ->(m, _) { anchor(m[0]) }]
            ].freeze

            # tips: [the page's Tips, {id => title}] or nil.
            def self.inline(text, tips = nil)
                kept = []
                out = shield(Text.escape(text), kept, tips)
                out = out.gsub(STRONG, '<strong>\1</strong>')
                out = out.gsub(EM) { emphasis(Regexp.last_match) }
                out.gsub(HOLE) { kept[Regexp.last_match(1).to_i] }
            end

            def self.shield(text, kept, tips)
                SHIELDED.reduce(text) do |out, (rx, build)|
                    out.gsub(rx) do
                        keep(kept, build.call(Regexp.last_match, tips))
                    end
                end
            end

            def self.emphasis(match) = "<em>#{match[1] || match[2]}</em>"

            def self.keep(kept, html)
                kept << html
                "\x00#{kept.length - 1}\x00"
            end

            def self.anchor(url)
                %(<a href="#{url}" rel="noopener noreferrer">#{url}</a>)
            end

            # A link; when its text is only an item id and the page holds
            # that item, the item's title follows as a tip.
            def self.link(label, href, tips = nil)
                rel = href.start_with?("#") ? "" : ' rel="noopener noreferrer"'
                open = %(<a href="#{href}"#{rel})
                title = titled(label, href, tips)
                return "#{open}>#{label}</a>" unless title

                attrs, box = tips.first.tip(Text.shorten(title, TIP_MAX))
                "#{open}#{attrs}>#{label}</a>#{box}"
            end

            def self.titled(label, href, tips)
                found = ID_HREF.match(href)
                return unless tips && found && BARE_ID.match?(label)
                return unless found[1] == label

                title = tips.last[label]
                title unless title.nil? || title.empty?
            end
        end
    end
end
