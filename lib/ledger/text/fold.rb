# frozen_string_literal: true

module Ledger
    module Text
        # Words compared as a reader would: every run of whitespace one
        # space, the ends trimmed, case folded. A brief carrying a
        # constraint and a transcript holding a quote are both judged on
        # this form, so a line break or a capital never hides a match.
        #
        #     Ledger::Text::Fold.fold("Keep  IT\nshort") # => "keep it short"
        module Fold
            module_function

            def fold(text)
                text.to_s.split(/[[:space:]]+/).reject(&:empty?)
                    .join(" ").downcase(:fold)
            end
        end
    end
end
