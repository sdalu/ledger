# frozen_string_literal: true

require "json"

require "ledger/abandon"

module Ledger
    module Commands
        # `show PATH [ID] [--json]`: the whole ledger as Markdown, or one
        # item as `key: value` lines; either one as JSON v1. PATH is a live
        # ledger's address or `L<id>`, live or closed; a closed one's
        # Markdown ends with the line saying how it closed (Abandon.line).
        class Show < CLI::Command
            USAGE = "PATH [ID]"
            LEDGER = /\AL([1-9]\d*)\z/
            SUMMARY = "the whole ledger as Markdown, or one item's fields " \
                      "and links"
            # The lists of the JSON document an id's letter is looked up in.
            LISTS = { "P" => %i[pieces], "O" => %i[questions closed_questions],
                      "D" => %i[criteria], "C" => %i[constraints],
                      "F" => %i[facts], "X" => %i[decisions] }.freeze
            UNKNOWN = "is no piece, question, criterion, fact, constraint, " \
                      "decision or noticed line of"

            private

            def flags(parser)
                parser.on("--json", "JSON v1") { @opts[:json] = true }
            end

            def run(path, ref = nil)
                id = row(path)[:id]
                snapshot = Snapshot.read(journal.db, id)
                return ledger(id, snapshot) unless ref

                item = item(id, snapshot, ref) or
                    refuse("#{ref} #{UNKNOWN} #{path}")
                @out.puts @opts[:json] ? json(item) : text(item)
                0
            end

            # The ledger row PATH names: an address, or L<id>.
            def row(path)
                match = LEDGER.match(path) or return journal.ledger(path)

                journal.ledger_by_id(match[1].to_i)
            end

            def ledger(id, snapshot)
                if @opts[:json]
                    @out.puts Render::Json.generate(Read.ledger(journal, id))
                else
                    @out.print Render::Markdown.render(snapshot)
                    closed = Abandon.line(journal.db, snapshot.ledger)
                    @out.puts "\n#{closed}" if closed
                end
                0
            end

            def item(id, snapshot, ref)
                return noticed(snapshot, ref) if ref.start_with?("Z")

                lists = LISTS.fetch(ref[0], [])
                doc = Read.ledger(journal, id)
                found = doc.values_at(*lists).flatten.find { it[:id] == ref }
                found && with_links(found, doc[:links], ref)
            end

            # A noticed line has the id of its row, nowhere else printed.
            def noticed(snapshot, ref)
                row = snapshot.noticed.find { "Z#{it[:id]}" == ref }
                { id: ref, line: row[:line] } if row
            end

            def with_links(item, links, ref)
                mine = links.select { it[:from] == ref }.group_by { it[:kind] }
                return item if mine.empty?

                targets = mine.transform_values { |list| list.map { it[:to] } }
                item.merge(links: targets)
            end

            def json(item)
                JSON.generate(schema: Render::Json::SCHEMA, kind: "item", item:)
            end

            # Scalars as `key: value`, lists joined by ` | `, a link kind
            # as its own line (`rests-on: F2, C3`), a piece's return as
            # its own line (`return: env, from back, TIME`).
            def text(item)
                links = item[:links] || {}
                [*item.except(:links, :returns).map do |key, value|
                    "#{key}: #{value(value)}"
                end,
                 *links.map do |kind, ids|
                     "#{kind.tr("_", "-")}: #{ids.join(", ")}"
                 end,
                 *returns(item)]
                    .join("\n")
            end

            def returns(item)
                item.fetch(:returns, []).map do |row|
                    "return: #{row[:cause]}, from #{row[:from]}, #{row[:at]}"
                end
            end

            def value(value)
                case value
                when Array then value.map { value(it) }.join(" | ")
                when Hash then value.map do |key, inner|
                    "#{key}=#{value(inner)}"
                end.join(", ")
                else value.to_s
                end
            end
        end
    end
end
