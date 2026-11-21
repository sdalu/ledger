# frozen_string_literal: true

require "digest"

require "ledger/pictures"

module Ledger
    module Commands
        # `mockup --piece P<n> --before|--after`: one file placed as one
        # side of a piece's before/after.
        module MockupPiece
            ID = /\AP[1-9]\d*\z/

            private

            def piece_flags(parser)
                parser.on("--piece ID", "the piece whose before/after it " \
                                        "is") { @opts[:piece] = it.strip }
                %w[before after].each do |role|
                    parser.on("--#{role}", "the piece as it is #{role}") do
                        (@opts[:roles] ||= []) << role
                    end
                end
            end

            def piece_mockup(path, sources)
                piece, role = piece_target(sources)
                item = one_file(sources)
                result = write(path) do |change|
                    place_side(change, piece, role, item, Address.parse(path))
                end
                @out.puts "placed #{item.file} as #{piece} #{role}"
                @out.puts status_line(result.after)
                0
            end

            def one_file(sources)
                items = Pictures::Sources.new(sources).items
                return items.first if items.one? && items.first.path.empty?

                refuse("--piece places one file, not a directory")
            end

            # [P<n>, before|after], refused unless they are whole.
            def piece_target(sources)
                piece = @opts[:piece]
                refuse("--question and --piece are exclusive") if
                    @opts.key?(:question)
                refuse("--piece takes a piece id, P<n>") unless ID.match?(piece)
                roles = @opts.fetch(:roles, []).uniq
                refuse("--piece places one side: --before or --after") unless
                    roles.one?
                refuse("--piece places one file") unless sources.one?
                [piece, roles.first]
            end

            def place_side(change, piece, role, item, address)
                row = change.resolve(piece).last
            rescue Unknown
                refuse("no #{piece} under Pieces in #{address}")
            else
                Pictures::Sides.new(change, journal.db)
                               .call(row, role, item,
                                     replace: @opts.fetch(:replace, false))
                change.summary = "placed #{item.name} as #{piece} #{role}"
            end
        end

        # `mockup PATH FILE|DIR... --question O<n> [--name NAME]
        # [--replace]`: the files are read into the journal as pictures,
        # and the question shows one name of them. `mockup PATH FILE
        # --piece P<n> --before|--after [--replace]`: one file, placed as
        # that side of the piece's before/after. Nothing is written on a
        # disk. `--replace` takes the question's other pictures away, or
        # the piece's earlier picture of that side; their blobs stay.
        class Mockup < CLI::Command
            include MockupPiece

            USAGE = "PATH FILE..."
            SYNOPSIS = "PATH FILE|DIR... --question O<n> | PATH FILE " \
                       "--piece P<n> --before|--after"
            SUMMARY = "read pictures into the journal for an open question " \
                      "or a piece's before/after"

            private

            def flags(parser)
                parser.on("--question ID", "the open question it is for") do |q|
                    @opts[:question] = q.strip
                end
                piece_flags(parser)
                parser.on("--name NAME", "the name the question shows") do |n|
                    @opts[:name] = n.strip
                end
                parser.on("--replace", "swap the question's pictures, or " \
                                       "the piece's of that side") \
                    { @opts[:replace] = true }
            end

            def arguments(args)
                return args if args.size >= 2

                refuse("usage: ledger mockup #{USAGE}")
            end

            def run(path, *sources)
                return piece_mockup(path, sources) if @opts.key?(:piece)

                question = question_id
                items = Pictures::Sources.new(sources).items
                result = write(path, own: question) do |change|
                    place(change, question, items, Address.parse(path))
                end
                report(result, question, Address.parse(path), items)
                0
            end

            # The question a picture is for, without a piece's flags.
            def question_id
                refuse("--before and --after are for --piece") if
                    @opts.key?(:roles)
                @opts.fetch(:question) do
                    refuse("a picture is always for a question or a " \
                           "piece: add --question O<n> or --piece P<n>")
                end
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
