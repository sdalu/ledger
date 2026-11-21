# frozen_string_literal: true

module Ledger
    module Text
        # A risk opens with its rating, "7/10 — what goes wrong": 0 is
        # nothing to lose, 10 the work or the data lost.
        module Risk
            RATING = %r{\A([0-9]+)/10(?: — |\z)}

            module_function

            # "7/10 — the cache goes stale" -> [7, "the cache goes stale"];
            # an unrated risk -> [nil, TEXT].
            def rating(text)
                text = text.strip
                match = RATING.match(text)
                return [nil, text] unless match

                [match[1].to_i, text[match.end(0)..].strip]
            end

            # What a case lacks, or nil: a problem, and a risk rated out
            # of ten.
            def case_problem(problem, risk)
                return "--problem: what is wrong or missing, and where" \
                    if problem.strip.empty?

                number, rest = rating(risk)
                if number.nil? || rest.empty?
                    '--risk "N/10 — what goes wrong", N from 0 to 10'
                elsif !number.between?(0, 10)
                    "a risk rated 0 to 10, not #{number}"
                end
            end
        end
    end
end
