# frozen_string_literal: true

require "digest"

require "ledger/pictures"

module Ledger
    module Commands
        # `mockup PATH FILE|DIR... --question O<n> [--name NAME]
        # [--replace]`: the files are read into the journal as pictures,
        # and the question shows one name of them. Nothing is written on
        # a disk. `--replace` takes the question's other pictures away;
        # their blobs stay.
        class Mockup < CLI::Command
            USAGE = "PATH FILE..."
            SYNOPSIS = "PATH FILE|DIR... --question O<n>"
            SUMMARY = "read pictures into the journal for an open question"

            private

            def flags(parser)
                parser.on("--question ID", "the open question it is for") do |q|
                    @opts[:question] = q.strip
                end
                parser.on("--name NAME", "the name the question shows") do |n|
                    @opts[:name] = n.strip
                end
                parser.on("--replace", "swap the question's pictures") do
                    @opts[:replace] = true
                end
            end

            def arguments(args)
                return args if args.size >= 2

                refuse("usage: ledger mockup #{USAGE}")
            end

            def run(path, *sources)
                question = @opts.fetch(:question) do
                    refuse("a picture is always for a question: add " \
                           "--question O<n>")
                end
                items = Pictures::Sources.new(sources).items
                result = write(path, own: question) do |change|
                    place(change, question, items, Address.parse(path))
                end
                report(result, question, Address.parse(path), items)
                0
            end

            # -> the name the question shows.
            def place(change, question, items, address)
                row = open_question(change, question) or
                    refuse("#{question} is not asked under Open in #{address}")
                name = shown(items)
                Pictures::Placement.new(change, journal.db)
                                   .call(row, items, name,
                                         replace: @opts.fetch(:replace, false))
                change.summary = "placed #{name}"
                name
            end

            def open_question(change, id)
                return unless id.match?(/\AO[1-9]\d*\z/)

                journal.db[:questions].where(ledger_id: change.ledger_id,
                                             n: id[1..].to_i,
                                             closed_at: nil).first
            end

            # The name the question shows, and the file its name opens on.
            def shown(items)
                names = items.map(&:name).uniq
                name = @opts[:name] || picked(items)
                unless names.include?(name)
                    refuse("--name #{name}: not among the names placed " \
                           "(#{names.join(", ")})")
                end
                return name if Pictures.page(items.select { it.name == name })

                refuse("no single page, image or text to pick in #{name}")
            end

            def picked(items)
                found = Pictures.page(items) and return found.name
                refuse("say which name the question shows, with --name " \
                       "(#{items.map(&:name).uniq.join(", ")})")
            end

            def report(result, question, address, items)
                items.each { @out.puts "placed #{it.file}" }
                line = Render::Markdown.line(result.after, question)
                @out.puts line.delete_prefix("- ")
                id = Digest::SHA1.hexdigest(address.to_s)[0, 10]
                @out.puts "viewer: /l/#{id} (the mockup at " \
                          "/m/#{id}/#{result.value})"
            end
        end
    end
end
