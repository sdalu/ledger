# frozen_string_literal: true

module Ledger
    module Checks
        # question-loop: an open question asked `--by` a piece that
        # awaits the user's word. The question waits on the piece and the
        # piece on the user, who has no way to answer it first.
        module Loops
            LOOP = "%s waits on %s, which waits on your %s: clear the " \
                   "link with ledger ask PATH %s --by none, or give %s its " \
                   "word"

            HINTS = {
                "question-loop" =>
                    "a question is not asked by a piece that awaits the " \
                    "user's word; `bin/ledger ask PATH O<n> --by none`, or " \
                    "`bin/ledger word PATH P<n> --word W` once given"
            }.freeze

            module_function

            def problems(derive)
                derive.open_questions.filter_map do |question|
                    piece = derive.held_by(question) or next
                    format(LOOP, derive.qref(question), derive.ref(piece),
                           derive.awaits_label(piece), derive.qref(question),
                           derive.ref(piece))
                end
            end
        end
    end
end
