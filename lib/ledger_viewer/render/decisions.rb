# frozen_string_literal: true

require "date"

require_relative "entry"
require_relative "text"

module LedgerViewer
    module Render
        # The Decisions fold's body: one h4 per date, newest first
        # ("today" for today), each with its rows in the ledger's order.
        # decision_row() and decisions_by_date() of ledger-serve.py.
        class Decisions
            LINE = /\A-[ ]\d{4}-\d{2}-\d{2}[ ]—[ ](.+?)[ ]—[ ]by[ ](user|me)
                    (?:[ ]\((.+?)\))?(?:[ ]—[ ]by[ ](user|me))?
                    (?:[ ]\((.+)\))?\z/x
            DATE = /\A- (\d{4}-\d{2}-\d{2}) — /
            IDENT = /\A([OP]\d+): /
            QUOTED = /\A"(?:[^"\\]|\\.)*"/
            # The parts of a parsed line: the words, who, the note.
            Parsed = Data.define(:words, :who, :note)

            def initialize(scope, entry)
                @scope = scope
                @entry = entry
            end

            # A line that does not parse keeps the plain row, in its
            # date's group when it starts with a date, else in a last
            # group without a heading.
            def html(lines)
                groups = group(lines)
                days = groups.keys.reject(&:empty?).sort.reverse
                days << "" if groups.key?("")
                days.map { day(it, groups[it]) }.join
            end

            private

            def group(lines)
                groups = Hash.new { |hash, day| hash[day] = [] }
                lines.each_with_index do |line, at|
                    groups[DATE.match(line)&.[](1) || ""] << row(line, at)
                end
                groups
            end

            def day(day, rows)
                head = day.empty? ? "" : "<h4>#{heading(day)}</h4>"
                "#{head}<ul class=\"entries\">#{rows.join}</ul>"
            end

            def heading(day)
                day == Date.today.iso8601 ? "today" : Text.escape(day)
            end

            def row(line, at)
                parsed = parse(line)
                return plain(line, at) unless parsed

                parts(parsed, at)
            end

            def plain(line, at)
                @entry.html(text: line.sub(/\A- /, ""), anchor: "dec-#{at}")
            end

            # "- DATE — what — why — by user|me", a note after it or a
            # repeated "by user" allowed; nil for any other line.
            def parse(line)
                found = LINE.match(line)
                return unless found && consistent?(found)

                Parsed.new(found[1], found[2], found[3] || found[5] || "")
            end

            def consistent?(found)
                (found[4].nil? || found[4] == found[2]) &&
                    !(found[3] && found[5])
            end

            def parts(parsed, at)
                words = parsed.words
                ident = IDENT.match(words)
                words = ident.post_match if ident
                what, why = split(words)
                mark = ident ? "#{@scope.chip(ident[1])} " : ""
                @scope.partial("ledger/decision",
                               { at:, mark:, what: @scope.inline(what),
                                 meta: meta(why, parsed) })
            end

            # A quoted choice is one piece: its own " — " does not split it.
            def split(words)
                cut = QUOTED.match(words)
                head, _, why = (cut ? cut.post_match : words).partition(" — ")
                ["#{cut&.[](0)}#{head}", why]
            end

            def meta(why, parsed)
                who = parsed.who == "user" ? "your call" : "the session's call"
                shown = [*why.split(" — "), who, parsed.note]
                shown.reject(&:empty?).map { @scope.inline(it) }.join(" · ")
            end
        end
    end
end
