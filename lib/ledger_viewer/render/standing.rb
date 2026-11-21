# frozen_string_literal: true

require_relative "helpers"

module LedgerViewer
    module Render
        # What the ledger page reads of a ledger beyond what the index
        # does: the parts of its document, and the numbers of the tiles.
        # Mixed into Reading.
        module Standing
            # The numbers the tiles and the head show: a question already
            # answered is the session's turn, not the user's, until filed.
            Figures = Data.define(:asks, :sent, :preparing, :out, :blocked,
                                  :planned, :deferred, :flying, :crit_met,
                                  :crit, :verified, :pieces, :kept, :waits)
            WORD_LEAD = "your word: "
            ITEM_BREAK = /, (?=P\d+ \()/

            def goals = @data.fetch("goals")

            # The constraints and facts as their objects: the line `show`
            # prints, and the pointer with its kind.
            def constraints = @data.fetch("constraints")

            def facts = @data.fetch("facts")

            # The decisions as the lines `show` prints them.
            def decisions = lines("decisions")

            # {id => {"kind" => letter, "line" => the line}}.
            def refs = @data.fetch("refs")

            def scope_lines = @data.fetch("noticed")

            def status = @data.fetch("status")

            # [{name, files: [{path, type, size}]}] of the ledger.
            def pictures = @data.fetch("pictures")

            # The entries sent from the viewer, each its payload's fields
            # with whether it was taken, when and whether it is malformed;
            # a malformed entry's whole line is its text.
            def inbox
                @inbox ||= @data.fetch("inbox").map { entry(it) }
            end

            # [[name, detail]] of the checks failing.
            def fails
                @data.fetch("fails").map { it.values_at("name", "detail") }
            end

            # {id => status} of every piece.
            def statuses = pieces.to_h { [it["id"], it["status"]] }

            # {id => whether the piece is settled} of every piece.
            def settled = pieces.to_h { [it["id"], it["settled"]] }

            # The questions answered and not filed yet.
            def sent_questions
                questions.select do |q|
                    !q["preparing"] && sent_answers.key?(q["id"])
                end
            end

            def prepared_questions = questions.select { it["preparing"] }

            # The unfinished pieces, the most urgent first.
            def flight
                order = Reading::IN_FLIGHT
                live = pieces.select { order.include?(it["status"]) }
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

            # The shape checks failing.
            def failing = fails

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
                live = pieces.reject { it["status"] == "dropped" }
                kept = live.count { it["status"] == "kept" }
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

            def lines(key) = @data.fetch(key).map { it["line"] }

            def entry(row)
                fields = if row["malformed"] then { "text" => row["payload"] }
                         else JSON.parse(row["payload"])
                         end
                fields.merge(row.slice("id", "taken", "taken_at", "malformed"))
            end

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
                  deferred: status_in(%w[deferred]),
                  flying: status_in(Reading::IN_FLIGHT) }
            end

            def status_in(list) = pieces.count { list.include?(it["status"]) }
        end
    end
end
