# frozen_string_literal: true

module LedgerViewer
    module Render
        # The pieces owed the user's word, and the piece building a
        # question (piece --builds): while that question is open, the
        # piece is drawn on the question's card, not on its own, so it is
        # not owed a word of its own. Mixed into Reading.
        module Building
            # The pieces that cannot move without the user's word.
            def owed
                pieces.reject { it["awaits"].empty? || building?(it) }
            end

            # The piece building the open question ID, or nil.
            def builder(id)
                return unless open_question?(id)

                pieces.find { it.dig("builds", "question") == id }
            end

            private

            def building?(piece)
                id = piece.dig("builds", "question")
                !id.nil? && open_question?(id)
            end

            def open_question?(id) = questions.any? { it["id"] == id }
        end
    end
end
