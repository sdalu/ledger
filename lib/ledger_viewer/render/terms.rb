# frozen_string_literal: true

module LedgerViewer
    module Render
        # The vocabulary of ledger.py the ledger page reads: what a
        # mockup is, which fields a line has, which words a piece can
        # await. Plain functions, ported one for one.
        module Terms
            MOCKUP_TYPES = {
                ".html" => "text/html; charset=utf-8",
                ".htm" => "text/html; charset=utf-8",
                ".css" => "text/css; charset=utf-8",
                ".js" => "text/javascript; charset=utf-8",
                ".json" => "application/json",
                ".txt" => "text/plain; charset=utf-8",
                ".svg" => "image/svg+xml", ".png" => "image/png",
                ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg",
                ".gif" => "image/gif", ".webp" => "image/webp",
                ".woff" => "font/woff", ".woff2" => "font/woff2",
                ".ttf" => "font/ttf"
            }.freeze
            MOCKUP_IMAGES = %w[.svg .png .jpg .jpeg .gif .webp].freeze
            FIELD = Regexp.new(
                "(?u) — (?:(done when|evidence): |(after|by): (?=P\\d)|" \
                "(for): (?=D\\d)|(see): (?=[CDFP]\\d)|(awaits): |" \
                "(problem|risk|plan|scope): )"
            )
            LINK = { "after" => /\AP\d+(?:, P\d+)*\z/,
                     "for" => /\AD\d+(?:, D\d+)*\z/, "by" => /\AP\d+\z/,
                     "see" => /\A[CDFP]\d+(?:, [CDFP]\d+)*\z/ }.freeze

            # What the page draws for each word a piece awaits.
            WORD_ICON = { "start" => "play", "commit" => "git",
                          "push" => "git", "merge" => "git",
                          "deploy" => "rocket", "other" => "check" }.freeze
            WORD_LABEL = { "start" => "Start", "commit" => "Commit",
                           "deploy" => "Deploy", "push" => "Push",
                           "merge" => "Merge", "other" => "Done" }.freeze
            # A section's icon, by its anchor; the same on its tile.
            SECTION_ICON = {
                "waiting" => "hand", "sent" => "send",
                "preparing" => "hourglass", "flight" => "list-todo",
                "criteria" => "list-checks", "checks" => "triangle-alert",
                "inbox" => "inbox", "record" => "archive", "goal" => "target"
            }.freeze

            module_function

            # The kind of an inbox entry by its ref: note, order, answer,
            # comment, or nil.
            def kind(ref)
                case ref
                when nil then "note"
                when "order" then "order"
                when /\AO\d+\z/ then "answer"
                when /\AP\d+\z/ then "comment"
                end
            end

            # 'A = keep as is' -> 'A'; an option without a meaning is its
            # own code.
            def option_code(option)
                Text.strip(option.partition(" = ").first)
            end

            # 'commit = merge it | deploy = ship it' -> [[word, what]], or
            # nil when a part is not `WORD = what` with both sides filled.
            def scope_words(value)
                pairs = value.split(" | ", -1).map do |part|
                    word, sep, what = part.partition(" = ")
                    [Text.strip(word), Text.strip(what)] unless sep.empty?
                end
                pairs unless pairs.empty? || pairs.any? { bare?(it) }
            end

            def bare?(pair) = pair.nil? || pair.any?(&:empty?)

            def awaits_label(words)
                words.map { |w, d| w == "other" ? "other (#{d})" : w }
                     .join(", ")
            end

            def kept?(status) = status.start_with?("kept:")

            # A piece another may wait for is done: verified, or kept.
            def settled?(status) = status == "verified" || kept?(status)

            # The ids a link field names, or nil when VALUE is not a list
            # of them.
            def link_ids(key, value)
                value = Text.strip(value)
                value.split(", ") if LINK.fetch(key).match?(value)
            end

            # [the text before its first field, {field => value}]: TEXT
            # cut at its field markers; `evidence:` runs to the end.
            def split_fields(text)
                marks = []
                text.scan(FIELD) do
                    marks << Regexp.last_match
                    break if marks.last[1] == "evidence"
                end
                [marks.empty? ? text : text[0...marks[0].begin(0)],
                 fields(text, marks)]
            end

            def fields(text, marks)
                marks.each_with_index.with_object({}) do |(mark, i), out|
                    stop = marks[i + 1]&.begin(0) || text.length
                    key = mark.captures.find(&:itself)
                    value = text[mark.end(0)...stop]
                    value = linked(out, key, value) if LINK.key?(key)
                    out[key] = value
                end
            end

            # A link is ids only and ends at the next dash; what follows
            # is kept as its tail.
            def linked(out, key, value)
                head, dash, rest = value.partition(" — ")
                out["tail:#{key}"] = dash + rest unless dash.empty?
                head
            end

            # Python's os.path.splitext, in two halves.
            def stem(base)
                at = base.rindex(".")
                at && base[0...at].match?(/[^.]/) ? base[0...at] : base
            end

            def ext(base) = base[stem(base).length..]
        end
    end
end
