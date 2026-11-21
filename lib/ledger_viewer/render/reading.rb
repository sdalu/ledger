# frozen_string_literal: true

require "json"
require "time"

require_relative "helpers"
require_relative "standing"
require_relative "terms"
require_relative "text"

module LedgerViewer
    module Render
        # A ledger as its JSON v1 document gives it (Ledger::Read, string
        # keys), with the derived views the pages compute from it: the
        # answers and words sent and not filed, what is owed, when a word
        # was first awaited, the index's state cell and counts. What the
        # index shows of a ledger is here.
        class Reading
            IN_FLIGHT = %w[blocked back out planned deferred].freeze
            MET = %w[x -].freeze
            # How many criteria, pieces and kept pieces a ledger counts.
            Counts = Data.define(:crit_met, :crit, :verified, :pieces, :kept)

            include Standing

            def initialize(data) = @data = data

            # The open questions, those being prepared among them.
            def questions = @data.fetch("questions")

            def pieces = @data.fetch("pieces")

            # The status line proposes the close, the Close offered.
            def ready_to_close? = status.end_with?("done: propose close")

            # The decisions' ids (X<n>), in the order of their lines.
            def decision_ids = @data.fetch("decisions").map { it["id"] }

            # {"O3" => ISO time, "P4:commit" => ISO time}.
            def asked = @data.fetch("asked")

            def criteria = @data.fetch("criteria")

            # The assumptions (state, fact, see, for), the decisions and
            # the links, as their objects.
            def assumptions = @data.fetch("assumptions")
            def decision_rows = @data.fetch("decisions")
            def links = @data.fetch("links")

            # When the ledger last changed: its last event.
            def updated = Time.iso8601(@data.fetch("ledger")["updated_at"])

            # A piece's words as [[word, what 'other' needs or ""]].
            def self.words(piece)
                piece["awaits"].map { [it["word"], it["what"].to_s] }
            end

            # A question's options as their lines, `A = what; cost`.
            def self.options(question)
                question["choices"].map { it["text"] }
            end

            # A criterion's text with its evidence or why, as its line
            # says it after the id.
            def self.criterion(criterion)
                criterion["line"].sub(/\A- \[.\] D\d+: /, "")
            end

            # A piece's title and detail as one line, `Title: detail`.
            def self.what(piece)
                detail = piece["detail"].to_s
                detail.empty? ? piece["title"] : "#{piece["title"]}: #{detail}"
            end

            # {O<n> => the latest answer sent and no session took}; a
            # comment on a question, or a picture asked, is no answer.
            def sent_answers
                @sent_answers ||= unfiled.each_with_object({}) do |entry, out|
                    ref = entry["ref"]
                    out[ref] = entry if ref.to_s.match?(/\AO\d+\z/) &&
                                        !Terms.aside?(entry)
                end
            end

            # {P<n> => the latest word sent on that piece, not filed}.
            def sent_words
                @sent_words ||= unfiled.select { sent_word?(it) }
                                       .to_h { [it["ref"], it] }
            end

            # The pieces that cannot move without the user's word.
            def owed = pieces.reject { it["awaits"].empty? }

            # When a piece's longest-awaited word was first seen, or "".
            def word_since(piece)
                keys = piece["awaits"].map { "#{piece["id"]}:#{it["word"]}" }
                keys.filter_map { asked[it] }.min_by { Time.iso8601(it) } || ""
            end

            # [rank, label]: lower ranks first.
            def summary
                return [0, "waiting on you"] if waiting?
                return [1, "answer sent"] if answered?
                return [1, "in flight"] if flying?
                return [2, "criteria open"] if open_criteria?

                [3, "ready to close"]
            end

            def counts
                live = pieces.reject { it["status"] == "dropped" }
                kept = live.count { it["status"] == "kept" }
                Counts.new(kept:, pieces: live.length - kept, **criteria_count,
                           verified: status_count("verified"))
            end

            # [the State cell, the line of what 'other' needs or ""]: the
            # words still owed once the sent ones are set aside, equal
            # words counted, then how many pieces' words are sent; the
            # ledger's own state when no word is owed. Both unescaped.
            def state_cell(fallback)
                tally, needs = tally_words
                return [fallback, ""] if tally.empty?

                sent = owed.count { sent_words.key?(it["id"]) }
                parts = tally.map { |w, n| n == 1 ? w : "#{w} ×#{n}" }
                parts[-1] += " · #{sent} sent" if sent.positive?
                [parts.join(", "), needs.join("; ")]
            end

            private

            def unfiled = inbox.reject { it["taken"] }

            def filled?(value) = Helpers.filled?(value)

            def sent_word?(entry)
                filled?(entry["word"]) && filled?(entry["ref"])
            end

            def status_count(status) = pieces.count { it["status"] == status }

            def criteria_count
                { crit: criteria.length,
                  crit_met: criteria.count { MET.include?(it["mark"]) } }
            end

            def open_criteria? = criteria.any? { it["mark"] == " " }

            def unprepared = questions.reject { it["preparing"] }

            def waiting?
                unprepared.any? { !sent_answers.key?(it["id"]) } ||
                    owed.any? { !sent_words.key?(it["id"]) }
            end

            def answered? = !unprepared.empty? || !owed.empty?

            def flying?
                questions.any? { it["preparing"] } ||
                    pieces.any? { IN_FLIGHT.include?(it["status"]) }
            end

            # [{word => how many pieces}, [what 'other' needs]].
            def tally_words
                tally = Hash.new(0)
                needs = []
                owed.each do |piece|
                    next if sent_words.key?(piece["id"])

                    Reading.words(piece).each do |word, desc|
                        tally[word] += 1
                        needs << desc if word == "other" && filled?(desc)
                    end
                end
                [tally, needs]
            end
        end
    end
end
