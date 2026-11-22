# frozen_string_literal: true

module Ledger
    module Text
        # The step risk: what the user's word itself puts at stake, read
        # off the word, whatever the work behind it. A word of its own
        # weighs start 0, commit 1, merge 2, push 4, deploy 5; an
        # irreversible piece adds 3 to each, capped at 10. `other (what)`
        # names no known step, so it weighs nothing and draws no meter.
        module StepRisk
            WEIGHTS = { "start" => 0, "commit" => 1, "merge" => 2,
                        "push" => 4, "deploy" => 5 }.freeze
            IRREVERSIBLE = 3
            CAP = 10

            module_function

            # WORD's step risk, nil for a word the table does not weigh.
            def of(word, irreversible: false)
                weight = WEIGHTS[word] or return

                [weight + (irreversible ? IRREVERSIBLE : 0), CAP].min
            end

            # The highest step risk of WORDS, nil when none is weighed: a
            # combined button's, and a piece's over the words it awaits.
            def max(words, irreversible: false)
                words.filter_map { of(it, irreversible:) }.max
            end
        end
    end
end
