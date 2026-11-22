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
                [since && "waiting #{Age.of(Ledger::Text.waited(since))}, " \
                          "since #{Text.minute(since)}",
                 (by.empty? ? nil : "prepared by #{by}"),
                 held(question)].compact.join(" · ")
            end

            # A question whose `by` piece awaits the user's word is
            # answered now: the piece moves only once that word is given.
            def held(question)
                id = question["held_by"] or return
                piece = @reading.pieces.find { it["id"] == id }
                words = Terms.awaits_label(Reading.words(piece))
                "#{id} waits for your #{words}; this question can be " \
                    "answered now"
            end

            def unready(question)
                prep = question["preparing"]
                "Not ready to answer#{preparing_line(question)}. It moves " \
                    "to Waiting on you when #{prep} is verified."
            end

            # What the preparing piece is doing: a deferred one waits on
            # an event, which is what the user needs to know.
            def preparing_line(question)
                prep = question["preparing"]
                piece = @reading.pieces.find { it["id"] == prep }
                if piece && piece["status"] == "deferred"
                    return ". Waits for #{prep}, #{deferred(piece)}"
                end

                ": #{prep} (#{question["preparing_status"]}) is still " \
                    "preparing #{unready_what(question)}"
            end

            def deferred(piece)
                cond = piece["until"].to_s
                cond.empty? ? "deferred" : "deferred until #{cond}"
            end

            def unready_what(question)
                return "it" if question["choices"].empty? &&
                               question["pictures"].none? { it["pending"] }

                "its options and mockups"
            end
        end
    end
end
