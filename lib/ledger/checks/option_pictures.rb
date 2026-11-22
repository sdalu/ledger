# frozen_string_literal: true

module Ledger
    module Checks
        # pictures-options: an open question where some options have a
        # picture and others none is announced, "O19: no picture for
        # options A, C", for the user compares the options by their
        # pictures. Never a failure: it fills the notes of a warning rule,
        # which has no problems, so --final and the write path pass it.
        module OptionPictures
            HINTS = {
                "pictures-options" =>
                    "an open question whose options have pictures shows one " \
                    "for each; `bin/ledger mockup PATH FILE --question " \
                    "O<n> --choice LABEL`; a warning only"
            }.freeze

            module_function

            def problems(_derive) = []
            def final(_derive) = []
            def compared(_derive) = []

            # One line for each open question lacking some.
            def notes(derive)
                derive.open_questions.filter_map { note(derive, it) }
            end

            def note(derive, question)
                rows = derive.snapshot.question_choices
                             .select { it[:question_id] == question[:id] }
                bare = rows.reject { derive.present?(it[:picture]) }
                return if bare.empty? || bare.size == rows.size

                "#{derive.qref(question)}: no picture for options " \
                    "#{bare.map { it[:label] }.join(", ")}"
            end
        end
    end
end
