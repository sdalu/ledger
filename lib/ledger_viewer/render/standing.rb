# frozen_string_literal: true

require_relative "helpers"

module LedgerViewer
    module Render
        # What the ledger page reads of a ledger beyond what the index
        # does: the parts of the dump, and the numbers of the tiles that
        # counts() of ledger-serve.py computes. Mixed into Reading.
        module Standing
            # The numbers the tiles and the head show: a question already
            # answered is the session's turn, not the user's, until filed.
            Figures = Data.define(
                :asks, :sent, :preparing, :out, :blocked, :planned,
                :flying, :crit_met, :crit, :verified, :pieces, :kept, :waits
            )
            WORD_LEAD = "your word: "
            ITEM_BREAK = /, (?=P\d+ \()/

            def goals = @data.fetch("goals")

            def constraints = @data.fetch("constraints")

            def facts = @data.fetch("facts")

            def refs = @data.fetch("refs")

            def decisions = @data.fetch("decisions")

            def scope_lines = @data.fetch("scope")

            def status = @data.fetch("status")

            def inbox = @data.fetch("inbox")

            def taken_at = @data.fetch("taken_at")

            def fails = @data.fetch("fails")

            # {id => status} of every piece.
            def statuses = pieces.to_h { [it["id"], it["status"]] }

            # The questions the user can answer now, in the page's order.
            def to_answer
                questions.select do |q|
                    q["id"] && !filled?(q["prep"]) &&
                        !sent_answers.key?(q["id"])
                end
            end

            # The questions asked of the user and not answered; one that
            # has no id is among them, to be flagged.
            def open_questions
                questions.reject do |q|
                    filled?(q["prep"]) || sent_answers.key?(q["id"])
                end
            end

            # The questions answered and not filed yet.
            def sent_questions
                questions.select do |q|
                    !filled?(q["prep"]) && sent_answers.key?(q["id"])
                end
            end

            def prepared_questions = questions.select { filled?(it["prep"]) }

            # The pieces whose word the user has not sent.
            def unsent_words = owed.reject { sent_words.key?(it["id"]) }

            # The unfinished pieces, the most urgent first.
            def flight
                order = Reading::IN_FLIGHT
                live = pieces.select do |p|
                    order.include?(p["status"]) || p["status"] == "unparsed"
                end
                live.sort_by.with_index do |p, i|
                    [order.index(p["status"]) || -1, i]
                end
            end

            # Nothing asked, sent, prepared, unfinished, unmet or failing:
            # the ledger is ready to close.
            def settled?
                [open_questions, sent_questions, prepared_questions, owed,
                 flight, unmet, failing].all?(&:empty?)
            end

            def unmet = criteria.select { [" ", "?"].include?(it["mark"]) }

            # The shape checks failing, but the open lines without an id,
            # which the page flags under Waiting on you.
            def failing = fails.reject { |pair| pair.first == "open" }

            # The messages sent and not taken.
            def said_count = inbox.count { !it["taken"] }

            # {id => the id of the next question to answer}.
            def next_of
                to_answer.each_cons(2).to_h { |a, b| [a["id"], b["id"]] }
            end

            # The entries the user sent on `ref` that no session took.
            def unfiled_on(ref)
                inbox.select { !it["taken"] && it["ref"] == ref }
            end

            def figures
                live = pieces.reject { Reading::DEAD.include?(it["status"]) }
                kept = live.count { it["status"].start_with?("kept:") }
                Figures.new(**asking, **flight_counts, **criteria_count,
                            verified: status_count("verified"),
                            pieces: live.length - kept, kept:,
                            waits: waits)
            end

            # The status line without the pieces whose word is sent.
            def status_text
                status.split(" · ", -1).filter_map { unsent(it) }.join(" · ")
            end

            private

            def unsent(part)
                return part unless part.start_with?(WORD_LEAD)

                items = part[WORD_LEAD.length..].split(ITEM_BREAK, -1)
                items = items.reject do |item|
                    sent_words.key?(item.partition(" ").first)
                end
                items.empty? ? nil : "#{WORD_LEAD}#{items.join(", ")}"
            end

            def asking
                held = sent_questions.length + owed.length - unsent_words.length
                { asks: open_questions.length + unsent_words.length,
                  sent: held, preparing: prepared_questions.length }
            end

            def flight_counts
                { out: status_in(%w[out back]), blocked: status_in(%w[blocked]),
                  planned: status_in(%w[planned]),
                  flying: status_in(Reading::IN_FLIGHT) }
            end

            def status_in(list) = pieces.count { list.include?(it["status"]) }

            # When the questions and words still owed were first seen.
            def waits
                words = owed.reject { sent_words.key?(it["id"]) }
                            .map { word_since(it) }
                (to_answer.filter_map { asked[it["id"]] } + words)
                    .reject(&:empty?)
            end
        end
    end
end
