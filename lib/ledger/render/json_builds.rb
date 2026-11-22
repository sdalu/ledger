# frozen_string_literal: true

module Ledger
    module Render
        class Json
            # What a piece names beside itself: `builds`, the question it
            # builds (piece --builds) with the decision that answered it
            # and that decision's text, both null while it is open; and
            # `obsoleted_by`, the piece that replaces it.
            class Builds
                def initialize(snapshot)
                    @questions = snapshot.questions.to_h { [it[:id], it] }
                    @pieces = snapshot.pieces.to_h { [it[:id], it[:n]] }
                    @decisions = snapshot.decisions.to_h { [it[:id], it] }
                    @answers = snapshot.links.select { answer?(it) }
                                       .to_h { [it[:to_row], it[:from_row]] }
                end

                def call(piece)
                    by = piece[:obsoleted_by_id]
                    { builds: builds(piece[:builds_id]),
                      obsoleted_by: by && "P#{@pieces.fetch(by)}" }
                end

                private

                def answer?(link)
                    link[:kind] == "answers" && link[:to_kind] == "O"
                end

                def builds(id)
                    return unless id

                    decision = @decisions[@answers[id]]
                    { question: "O#{@questions.fetch(id)[:n]}",
                      decision: decision && "X#{decision[:n]}",
                      text: decision&.fetch(:body) }
                end
            end
        end
    end
end
