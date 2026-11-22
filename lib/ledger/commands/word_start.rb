# frozen_string_literal: true

require "ledger/text/awaits"

module Ledger
    module Commands
        # The start of a piece that builds a question (piece --builds):
        # refused while that question is open, since the start would act
        # before the answer the piece is built from. Mixed into Word.
        module WordStart
            private

            def built!(piece, given)
                return unless piece[:builds_id] && start?(given)

                n = journal.db[:questions].where(id: piece[:builds_id],
                                                 closed_at: nil).get(:n)
                refuse("P#{piece[:n]} builds O#{n}: answer O#{n} first") if n
            end

            def start?(given)
                Text::Awaits.split(given).map(&:strip).include?("start")
            end
        end
    end
end
