# frozen_string_literal: true

require "ledger/commands/answer"
require "ledger/commands/decide"
require "ledger/commands/word_start"
require "ledger/text/awaits"

module Ledger
    module Commands
        # `word PATH P<n> --word W [--date] [--take N…]`: the user's word on
        # a piece becomes a decision by user with a led_to edge to it, and
        # the piece changes: `drop` drops it, any other word must be one it
        # awaits and stops being awaited, its scope line going with it.
        # A piece that builds a question still open takes no start: the
        # answer comes first (WordStart). Without --take the user must
        # have written since the piece asked (Taking).
        class Word < CLI::Command
            include Taking
            include WordStart

            USAGE = "PATH ID"
            SYNOPSIS = "PATH P<n> --word W"
            SUMMARY = "file the user's word on a piece as a decision by user " \
                      "and act on the piece"
            OPTIONS = {
                word: ["--word WORD",
                       "the words given, among those it awaits, or drop"],
                date: ["--date DATE", DATE]
            }.freeze
            ID = /\AP[1-9]\d*\z/

            private

            def flags(parser)
                take_flag(parser)
                dry_run(parser)
            end

            def run(path, id)
                refuse("the target is P<n>") unless ID.match?(id)
                given = need(:word).strip
                ids = takes
                result = write(path, own: id) do |change|
                    give(change, find(change, id, path), given, ids)
                end
                report(result, path, id, ids)
                0
            end

            def find(change, id, path)
                change.resolve(id).last
            rescue Unknown
                refuse("no #{id} under Pieces in #{Address.parse(path)}")
            end

            def give(change, piece, given, ids)
                refuse("--word is empty") if given.empty?
                built!(piece, given)
                remove(change, piece, left(change, piece, given))
                take(change, ids, asked: [:pieces, piece[:id]])
                ref = decision(change, piece, given, ids)
                change.link("led_to", ref, "P#{piece[:n]}")
                ref
            end

            # The awaits rows the piece keeps: none once dropped.
            def left(change, piece, given)
                return remaining(piece, given) unless given == "drop"

                drop(change, piece)
            end

            def drop(change, piece)
                change.status(piece[:id], "dropped")
                []
            end

            # The awaits rows left once each word GIVEN names is given.
            def remaining(piece, given)
                rows = awaits(piece)
                refuse("P#{piece[:n]} awaits no word") if rows.empty?
                Text::Awaits.split(given).map(&:strip).reject(&:empty?)
                            .each do |name|
                    hit = rows.find { names?(it, name) } or
                        refuse("P#{piece[:n]} does not await \"#{name}\" " \
                               "(awaits: #{label(piece)})")
                    rows.delete(hit)
                end
                rows
            end

            def names?(row, name)
                name == row[:word] ||
                    (row[:word] == "other" && name == "other (#{row[:what]})")
            end

            def awaits(piece)
                journal.db[:piece_awaits].where(piece_id: piece[:id])
                       .order(:position, :id).all
            end

            def label(piece)
                Text::Awaits.label(awaits(piece).map { [it[:word], it[:what]] })
            end

            # Delete the awaits rows given and the scope rows of words no
            # longer awaited.
            def remove(change, piece, left)
                (awaits(piece) - left).each do |row|
                    change.delete(:piece_awaits, row[:id])
                end
                words = left.map { it[:word] }
                journal.db[:piece_scopes].where(piece_id: piece[:id])
                       .exclude(word: words).select_map(:id)
                       .each { change.delete(:piece_scopes, it) }
            end

            def decision(change, piece, given, ids)
                src = " (#{ids.join(", ")}, from the viewer)" if ids.any?
                body = "P#{piece[:n]}: \"#{given}\"#{src}"
                date = @opts.fetch(:date) { Time.now.strftime("%F") }
                refuse("not a decision line: - #{date} — #{body} — by user") \
                    unless Decide::LINE.match?("- #{date} — #{body} — by user")
                n = change.next_id("X")
                change.insert(:decisions, n:, date:, body:, by: "user")
                "X#{n}"
            end

            def report(result, path, id, ids)
                ref = result.value
                lines = [Render::Markdown.line(result.after, ref),
                         Render::Markdown.line(result.after, id)]
                lines << take_line(result.after, ids) if ids.any? &&
                                                         !result.dry
                emit(result, path, first: ref, lines:)
            end
        end
    end
end
