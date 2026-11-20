# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # The lines a question's card says about it: the label of its
        # form, how long it has waited, why it is not ready. Mixed into
        # Cards, which holds the reading.
        module QuestionMeta
            private

            # The label of the form that answers the question.
            def label(question)
                id = question["id"]
                choices = !question["choices"].empty?
                if choices && !question["items"].empty?
                    "Your choice per item for #{id}"
                elsif choices then "Your choice for #{id}"
                else
                    "Your answer to #{id}"
                end
            end

            def waiting_since(question)
                since = @reading.asked[question["id"]]
                by = question["by"].to_s
                [since && "waiting #{Text.waited(since)}, " \
                          "since #{since[0, 16]}",
                 (by.empty? ? nil : "prepared by #{by}")].compact.join(" · ")
            end

            def unready(question)
                prep = question["prep"]
                "Not ready to answer: #{prep} (#{question["prep_status"]}) " \
                    "is still preparing #{unready_what(question)}. It moves " \
                    "to Waiting on you when #{prep} is verified."
            end

            def unready_what(question)
                return "it" if question["choices"].empty? &&
                               !Text::PENDING.match?(question["text"])

                "its options and mockups"
            end
        end
    end
end
