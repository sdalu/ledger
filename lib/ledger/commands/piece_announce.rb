# frozen_string_literal: true

require "ledger/text/announce"

module Ledger
    module Commands
        # `piece PATH P<n> --announce FILE`: the ANNOUNCE block of one
        # dispatch of the piece, read from FILE (`-` for stdin), stored
        # parsed as a piece_assessments row of the write's event. Each
        # call is a row of its own, a retry's or a fan-out's identical
        # block too. It changes nothing else, so it goes alone, but for
        # `--session`.
        class PieceAnnounce
            # The options that may go with --announce.
            ALONGSIDE = %w[announce session].freeze

            def initialize(opts, target, session)
                @opts = opts
                @target = target
                @session = session
                alone!
            end

            # The block read and parsed before the write opens, so a
            # refusal leaves no event.
            def block
                @block ||= Text::Announce.parse(read(@opts["announce"]))
            end

            # Inside the write: the row, on the piece TARGET names.
            def call(change, path)
                piece = find(change, path)
                change.insert(:piece_assessments, piece_id: piece[:id],
                                                  session: @session,
                                                  **block.to_h)
            end

            private

            def alone!
                fail!("--announce needs a piece, P<n>, not new") unless
                    Piece::ID.match?(@target)
                others = @opts.keys.map(&:to_s) - ALONGSIDE
                return if others.empty?

                fail!("--announce goes alone: drop " \
                      "#{others.map { "--#{it.tr("_", "-")}" }.join(", ")}.")
            end

            def read(file)
                return $stdin.read.force_encoding(Encoding::UTF_8) if
                    file == "-"

                File.read(file, encoding: Encoding::UTF_8)
            rescue SystemCallError => e
                fail!("--announce cannot read #{file}: #{e.message}.")
            end

            def find(change, path)
                change.resolve(@target).last
            rescue Unknown
                fail!("there is no #{@target} under Pieces in " \
                      "#{Address.parse(path)}.")
            end

            def fail!(message) = raise(Refused, message)
        end
    end
end
