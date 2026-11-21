# frozen_string_literal: true

require "ledger/text/options"
require "ledger/text/picker"
require "ledger/text/title"

module Ledger
    module Checks
        # The rules on the open questions: open-choices, open-described,
        # open-picker, their part of titles and details, and of
        # case-rated. A closed question is in none of them.
        module Open
            BARE = "what %s does (`X = what it does, what it costs`)"
            RECOMMEND = "`— recommend: X, why`"
            NO_RISK = "an open question without a `— risk: N/10 — …`"
            UNRATED = "an open question whose risk is unrated"

            module_function

            # An option with a colon, items without choices, a drop or
            # ignore option.
            def choices(derive)
                derive.open_questions.flat_map do |question|
                    Text::Options.shape_problems(derive.options(question),
                                                 derive.items(question))
                                 .map { "#{derive.qref(question)} (#{it})" }
                end
            end

            # A problem and a risk; once answerable, what each option does
            # and the recommended one.
            def described(derive)
                derive.open_questions.filter_map do |question|
                    missing = case_missing(derive, question) +
                              pick_missing(derive, question)
                    next if missing.empty?
                    "#{derive.qref(question)} needs #{missing.join(", ")}"
                end
            end

            def case_missing(derive, question)
                %i[problem risk].reject { derive.present?(question[it]) }
                                .map { "`— #{it}:`" }
            end

            def pick_missing(derive, question)
                opts = derive.options(question)
                return [] if opts.empty? || !derive.answerable?(question)
                bare = opts.reject { it.include?(" = ") }
                [(format(BARE, bare.join(", ")) if bare.any?),
                 (RECOMMEND unless derive.present?(question[:recommend]))]
                    .compact
            end

            # The picker grammar on every open question, after any edit,
            # and no two open questions offering the same options (G9).
            def picker(derive)
                broken = derive.open_questions.filter_map do |question|
                    problems, = picker_problems(derive, question)
                    "#{derive.qref(question)}: #{problems.join("; ")}" \
                        if problems.any?
                end
                offered = derive.open_questions.map do |question|
                    [derive.qref(question), derive.options(question)]
                end
                broken + Text::Picker.duplicates(offered)
            end

            def picker_problems(derive, question)
                Text::Picker.problems(detail: question[:detail],
                                      opts: derive.options(question),
                                      items: derive.items(question),
                                      recommend: question[:recommend].to_s,
                                      ready: derive.answerable?(question))
            end

            def titles(derive)
                each_problem(derive) { Text::Title.problem(it[:title]) }
            end

            def details(derive)
                each_problem(derive) { Text::Title.detail_problem(it[:detail]) }
            end

            # Each open question's risk, missing or unrated.
            def rated(derive)
                each_problem(derive) do |question|
                    if !derive.present?(question[:risk]) then NO_RISK
                    elsif question[:risk_rating].nil? then UNRATED
                    end
                end
            end

            def each_problem(derive)
                derive.open_questions.filter_map do |question|
                    why = yield(question)
                    "#{derive.qref(question)}: #{why}" if why
                end
            end
        end
    end
end
