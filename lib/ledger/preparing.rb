# frozen_string_literal: true

module Ledger
    # What an open question waits on (docs/journal.md, section 3): the
    # pieces preparing it, and the one that holds it only for the user's
    # word. Mixed into Derive, which holds the pieces and their rows.
    module Preparing
        # The piece that still prepares QUESTION: its `by` piece, then the
        # pieces its pending pictures name, the first not settled; nil
        # when the question is answerable.
        def preparer(question) = preparers(question).find { !settled?(it) }
        def answerable?(question) = preparer(question).nil?

        # The pieces QUESTION waits on: its `by` piece unless that one
        # awaits the user's word (`held_by`), then the pieces its pending
        # pictures name.
        def preparers(question)
            pending = rows(:question_pictures, :question_id, question)
                      .filter_map { it[:pending_id] }
            by = question[:by_id] unless held_by(question)
            [by, *pending].compact.map { piece(it) }
        end

        # The `by` piece of QUESTION when it is not settled and awaits
        # the user's word: it moves only once given it, so the question
        # cannot wait for it; nil otherwise.
        def held_by(question)
            held = question[:by_id] && piece(question[:by_id])
            held if held && !settled?(held) && awaits(held).any?
        end
    end
end
