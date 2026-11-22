# frozen_string_literal: true

require "digest"

require "ledger/commands/mockup_choice"
require "ledger/pictures"

module Ledger
    module Commands
        # `mockup --piece P<n> --before|--after`: one file placed as one
        # side of a piece's before/after; it ends the redraw `piece
        # --picture-pending` announced.
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
                exclusive
                refuse("--piece takes a piece id, P<n>") unless ID.match?(piece)
                roles = @opts.fetch(:roles, []).uniq
                refuse("--piece places one side: --before or --after") unless
                    roles.one?
                refuse("--piece places one file, not several") unless
                    sources.one?
                [piece, roles.first]
            end

            def exclusive
                refuse("--question and --piece are exclusive") if
                    @opts.key?(:question)
                refuse("--choice is for --question, not --piece") if
                    @opts.key?(:choice)
            end

            def place_side(change, piece, role, item, address)
                row = change.resolve(piece).last
            rescue Unknown
                refuse("no #{piece} under Pieces in #{address}")
            else
                Pictures::Sides.new(change, journal.db)
                               .call(row, role, item,
                                     replace: @opts.fetch(:replace, false))
                redrawn(change, row)
                change.summary = "placed #{item.name} as #{piece} #{role}"
            end

            def redrawn(change, row)
                return unless row[:picture_pending]

                change.update(:pieces, row[:id], picture_pending: nil)
            end
        end

        # `mockup PATH FILE|DIR... --question O<n> [--name NAME]
        # [--replace]`: the files are read into the journal as pictures,
        # and the question shows every name of them (a DIR
        # by the file it opens on, Pictures.pick). `mockup PATH FILE
        # --piece P<n> --before|--after [--replace]`: one file, placed as
        # that side of the piece's before/after. `mockup PATH FILE
        # --question O<n> --choice LABEL`: one file, placed as that
        # option's own picture. Nothing is written on a disk. `--replace`
        # takes the question's other pictures away, or the piece's
        # earlier picture of that side, or the option's; their blobs stay.
        class Mockup < CLI::Command
            include MockupPiece
            include MockupChoice

            USAGE = "PATH FILE..."
            SYNOPSIS = "PATH FILE|DIR... --question O<n> | PATH FILE " \
                       "--question O<n> --choice LABEL | PATH FILE " \
                       "--piece P<n> --before|--after"
            SUMMARY = "read pictures into the journal for an open question " \
                      "or a piece's before/after"

            private

            def flags(parser)
                parser.on("--question ID", "the open question it is for") do |q|
                    @opts[:question] = q.strip
                end
                piece_flags(parser)
                choice_flags(parser)
                parser.on("--name NAME", "the name the question shows") do |n|
                    @opts[:name] = n.strip
                end
                replace_flag(parser)
            end

            def replace_flag(parser)
                parser.on("--replace", "swap the question's pictures, the " \
                                       "piece's of that side, or the " \
                                       "option's") \
                    { @opts[:replace] = true }
            end

            def arguments(args)
                return args if args.size >= 2

                refuse("usage: ledger mockup #{USAGE}")
            end

            def run(path, *sources)
                return piece_mockup(path, sources) if @opts.key?(:piece)
                return choice_mockup(path, sources) if @opts.key?(:choice)

                question_mockup(path, sources)
            end

            def question_mockup(path, sources)
                question = question_id
                refuse("--name names one FILE or DIR, not several") if
                    @opts.key?(:name) && sources.size > 1
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

            # -> [[name, the file it opens on]] the question shows.
            def place(change, question, items, address)
                row = open_question(change, question) or
                    refuse("#{question} is not asked under Open in #{address}")
                shown = shown(items)
                names = shown.map(&:first)
                Pictures::Placement.new(change, journal.db)
                                   .call(row, items, names,
                                         replace: @opts.fetch(:replace, false))
                change.summary = "placed #{names.join(", ")}"
                shown
            end

            def open_question(change, id)
                return unless id.match?(/\AO[1-9]\d*\z/)

                journal.db[:questions].where(ledger_id: change.ledger_id,
                                             n: id[1..].to_i,
                                             closed_at: nil).first
            end

            # Every name placed is shown, a DIR by the file it opens on.
            def shown(items)
                shown = Pictures.shown(items)
                name = @opts[:name] or return shown
                return shown if shown.assoc(name)

                refuse("--name #{name}: not among the names placed " \
                       "(#{shown.map(&:first).join(", ")})")
            end

            def report(result, question, address, items)
                items.each { @out.puts "placed #{it.file}" }
                line = Render::Markdown.line(result.after, question)
                @out.puts line.delete_prefix("- ")
                id = Digest::SHA1.hexdigest(address.to_s)[0, 10]
                urls = result.value.map { "/m/#{id}/#{it.last}" }
                word = urls.size > 1 ? "mockups" : "mockup"
                @out.puts "viewer: /l/#{id} (the #{word} at #{urls.join(", ")})"
            end
        end
    end
end
