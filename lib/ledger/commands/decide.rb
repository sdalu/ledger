# frozen_string_literal: true

require "ledger/asked_since"
require "ledger/commands/heard"

module Ledger
    module Commands
        # `decide PATH TEXT --by user|me [--note] [--date] [--rests-on]
        # [--led-to] [--replaces X<n>]`: a decision, with an edge to each
        # item it rests on, led to or replaces. A decision by user must
        # follow a message of the user's (Heard), written after the
        # question it answers and the pieces it led to asked.
        class Decide < CLI::Command
            include Heard

            USAGE = "PATH TEXT"
            SYNOPSIS = "PATH TEXT --by user|me"
            SUMMARY = "a decision, who made it, and what it rests on, led to " \
                      "or replaces"
            OPTIONS = {
                by: ["--by WHO", "user (it binds) or me (reviewable)"],
                note: ["--note NOTE",
                       "a note after who decided, no parentheses"],
                date: ["--date DATE", DATE]
            }.freeze
            # The decision line's shape, a note holding no parenthesis.
            LINE = Regexp.new('\A- (\d{4}-\d{2}-\d{2}) — (.+) — by (user|me)' \
                              '(?: \(([^()]*)\))?\z')
            SUBJECT = /\A(O[0-9]+):/
            # Each edge flag: its link kind and the letters of the items it
            # may name.
            EDGES = { "--rests-on" => %w[rests_on FC],
                      "--led-to" => %w[led_to PO],
                      "--replaces" => %w[replaces X] }.freeze
            # What each edge flag names, as the help says it.
            NAMES = { "--rests-on" => "F<n>,C<n>... it rests on",
                      "--led-to" => "P<n>,O<n>... it led to",
                      "--replaces" => "X<n>, the decision it replaces" }.freeze

            private

            def flags(parser)
                EDGES.each_key { |flag| edge_flag(parser, flag) }
                dry_run(parser)
            end

            def edge_flag(parser, flag)
                parser.on("#{flag} IDS", NAMES.fetch(flag)) { @opts[flag] = it }
            end

            def run(path, text)
                refuse("--by is user or me") unless %w[user
                                                       me].include?(@opts[:by])
                row = row(line(text, "the decision"))
                links = edges
                heard!(since(path, row[:subject], links)) if
                    @opts[:by] == "user"
                add_item(path, "X", :decisions, own: row[:body],
                                                **row) do |change, ref|
                    links.each { |kind, to| change.link(kind, ref, to) }
                end
            end

            def row(body)
                date = @opts.fetch(:date) { Time.now.strftime("%F") }
                note = @opts[:note].to_s.strip
                text = "- #{date} — #{body} — by #{@opts[:by]}"
                text += " (#{note})" unless note.empty?
                LINE.match?(text) or refuse("not a decision line: #{text}")
                { date:, body:, by: @opts[:by], note: (note unless note.empty?),
                  subject: body[SUBJECT, 1] }
            end

            # [[link kind, "F2"]] for every edge flag given.
            def edges
                EDGES.flat_map do |flag, (kind, letters)|
                    ids(@opts[flag]).map do |ref|
                        unless letters.include?(ref[0])
                            refuse("#{flag} takes #{letters.chars.join("/")} " \
                                   "ids, not #{ref}")
                        end
                        [kind, ref]
                    end
                end
            end

            # The newest ask among the question the body opens with and
            # the pieces it led to; 0 with neither.
            def since(path, subject, links)
                ledger = journal.ledger(path)[:id]
                refs = [subject, *links.filter_map do |kind, ref|
                    ref if kind == "led_to" && ref.start_with?("P")
                end]
                asks = refs.compact.filter_map do |ref|
                    AskedSince.ref(journal.db, ledger, ref)
                end
                asks.max || 0
            end

            def ids(value) = value.to_s.split(/[,\s]+/).reject(&:empty?)
        end
    end
end
