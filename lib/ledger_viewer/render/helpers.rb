# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # The small builders the pages share: chip(),
        # project_name(), answer_label(), answer_summary() and the
        # time's spelling. Plain functions, no page in them.
        module Helpers
            ID_CHIP = /\A([A-Z])([0-9]+)\z/
            LEDGER_NAME = /\ALEDGER-(.+)\.md\z/
            LINE_BREAKS = /\r\n|[\n\r\v\f\x1c-\x1e\u0085  ]/

            # What the ids and the colours mean, as the legend folds them.
            LEGEND_IDS = [
                ["P", "a piece of work, done by a delegate, another " \
                      "session or the session itself"],
                ["O", "a question for you"],
                ["D", "a criterion: what \u201cdone\u201d is checked by"],
                ["C", "a constraint you set"],
                ["F", "a fact the session found"],
                ["N", "something you sent from this viewer"]
            ].freeze
            LEGEND_COLOURS = [
                ["is-ask", "your turn: a question, a word"],
                ["is-flight", "the session's turn: work in flight, your " \
                              "answer not filed yet"],
                ["is-done", "settled: verified, met, filed"],
                ["is-fail", "wrong or blocked"]
            ].freeze
            # The row's class, by rank.
            KIND = %w[is-ask is-flight is-flight is-done is-fail].freeze

            module_function

            # A tag chip; an item id is drawn in two halves, the letter on
            # a pale ground and the number on the chip's own.
            def chip(text, attrs = "")
                found = ID_CHIP.match(text)
                return plain_chip(text, attrs) unless found

                halves = "<span class=\"l\">#{found[1]}</span>" \
                         "<span class=\"n\">#{found[2]}</span>"
                %(<span class="tag is-split"#{attrs}>#{halves}</span>)
            end

            def plain_chip(text, attrs)
                %(<span class="tag"#{attrs}>#{Text.escape(text)}</span>)
            end

            # The project's directory name; a ledger named LEDGER-SFX.md is
            # one of several in that project, so its suffix follows.
            def project_name(project, path)
                name = File.basename(project.sub(%r{/+\z}, ""))
                name = project if name.empty?
                suffix = LEDGER_NAME.match(File.basename(path))
                suffix ? "#{name} · #{suffix[1]}" : name
            end

            # The awaited words without what 'other' needs.
            def bare_label(words) = words.map(&:first).join(", ")

            # The queue row's link: Review WORDS, or Open when only
            # 'other' awaits.
            def answer_label(words)
                return "Open" if words.all? { it.first == "other" }

                "Review #{bare_label(words)}"
            end

            # An inbox answer in one line: the word, the choice or the
            # picks, else its text.
            def answer_summary(entry)
                return "word: #{entry["word"]}" if filled?(entry["word"])
                return "chose #{entry["choice"]}" if filled?(entry["choice"])
                return picks(entry["picks"]) if filled?(entry["picks"])

                first_line(entry["text"])
            end

            # The same answer as [lead, head, rest]: a choice is "chose ",
            # its option up to the first ':' or ';', then the rest of it,
            # so a one-row receipt can show what was chosen and no more.
            def answer_parts(entry)
                choice = entry["choice"]
                if filled?(choice) && !filled?(entry["word"])
                    head, rest = choice.split(/(?=[:;])/, 2)
                    return ["chose ", head, rest.to_s]
                end

                ["", answer_summary(entry), ""]
            end

            def picks(picks)
                picks.map { |item, pick| "#{item}: #{pick}" }.join("; ")
            end

            def first_line(text)
                lines = Text.strip(text).split(LINE_BREAKS)
                return "comments only" if lines.empty?

                cut = lines.first.length > 120 || lines.length > 1
                lines.first[0, 120] + (cut ? "…" : "")
            end

            def filled?(value) = ![nil, "", false, {}, []].include?(value)

            # "s" for more than one.
            def plural(count) = count > 1 ? "s" : ""

            # A thin bar filled to done/total; a half rounds to the
            # even number.
            def bar(done, total)
                pct = 0
                if total.positive?
                    pct = (100.0 * done / total).round(half: :even)
                end
                '<span class="bar" aria-hidden="true"><span ' \
                    "style=\"inline-size: #{pct}%\"></span></span>"
            end

            def risk_band(rating)
                if rating >= 7 then "is-high"
                elsif rating >= 4 then "is-mid"
                else "is-low"
                end
            end

            def when_text(time)
                Time.at(time).localtime.strftime("%Y-%m-%d %H:%M")
            end
        end
    end
end
