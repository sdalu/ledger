# frozen_string_literal: true

module Ledger
    module Commands
        # `piece PATH P<n> --status back --handback`: a delegate's hand-back,
        # run by the delegation skill's hook when the delegate stops. A
        # piece out goes back; a piece in any other status is left as it
        # is, said in one sentence and exit 0, since the hook must never
        # move a piece further than back nor block the stop. The hook
        # shows the last line printed, so each outcome is one sentence.
        module PieceHandback
            # The options that may go with --handback.
            ALONGSIDE = %w[handback status].freeze

            private

            def handback(path, target)
                handback_alone(target)
                found = handback_status(path, target)
                unless found == "out"
                    @out.puts "#{target} is #{found}; the hand-back " \
                              "changes nothing"
                    return 0
                end
                save(path, target, session)
                @out.puts "hand-back recorded on #{path} #{target}"
                0
            end

            def handback_alone(target)
                refuse("--handback needs a piece, P<n>, not #{target}.") unless
                    Piece::ID.match?(target)
                others = @opts.keys.map(&:to_s) - ALONGSIDE
                unless others.empty?
                    refuse("--handback goes with --status back alone: drop " \
                           "#{others.map { "--#{it.tr("_", "-")}" }
                                    .join(", ")}.")
                end
                return if @opts["status"]&.strip == "back"

                refuse("--handback goes with --status back alone.")
            end

            def handback_status(path, target)
                ledger = journal.ledger(path)
                status = journal.db[:pieces]
                                .where(ledger_id: ledger[:id],
                                       n: target[1..].to_i).get(:status)
                return status if status

                refuse("there is no #{target} under Pieces in " \
                       "#{Address.parse(path)}.")
            end
        end
    end
end
