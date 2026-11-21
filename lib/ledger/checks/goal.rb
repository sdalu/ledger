# frozen_string_literal: true

require "ledger/text/title"

module Ledger
    module Checks
        # goal-titled, goal-revision and the Goal part of case-rated. An
        # empty In short or Context line is the schema's to refuse.
        module Goal
            TITLED = "a Goal's Title reads as a title and its In short " \
                     "and Context lines are not empty: "
            GO_AHEAD = 'a go-ahead ("do", "next") goes under Decisions, ' \
                       "not into a goal revision"
            REVISION_WORDS = 4
            LATEST = { "Title" => :title, "In short" => :short }.freeze

            module_function

            # Each Goal block whose Title fails the title rule.
            def titled(derive)
                derive.snapshot.goals.filter_map do |goal|
                    why = goal[:title] && Text::Title.problem(goal[:title])
                    "#{head(goal)} #{why}" if why
                end
            end

            # Each revised Goal block quoting fewer than four words.
            def revision(derive)
                derive.snapshot.goals.filter_map do |goal|
                    next unless goal[:revised]
                    head(goal) if goal[:quote].split.size < REVISION_WORDS
                end
            end

            # The latest Goal block without its Title or In short.
            def rated(derive)
                goal = derive.snapshot.goals.last or return []
                LATEST.filter_map do |label, key|
                    next if derive.present?(goal[key])
                    "the latest Goal block without `#{label}:`"
                end
            end

            # The block's label line, as the Markdown shows it.
            def head(goal) = "Goal G#{goal[:n]} (#{goal[:stamp]}):"
        end
    end
end
