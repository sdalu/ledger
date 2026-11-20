# frozen_string_literal: true

require_relative "helpers"
require_relative "standing"
require_relative "text"

module LedgerViewer
    module Render
        # A ledger as ledger-dump.py gives it (a Hash, string keys), with
        # the derived views ledger-serve.py's summary(), sent_answers(),
        # sent_words(), owed(), word_since(), state_cell() and counts()
        # compute from it. What the index shows of a ledger is here.
        class Reading
            IN_FLIGHT = %w[blocked back out planned].freeze
            MET = %w[x -].freeze
            DEAD = %w[dropped unparsed].freeze
            # How many criteria, pieces and kept pieces a ledger counts.
            Counts = Data.define(:crit_met, :crit, :verified, :pieces, :kept)

            include Standing

            def initialize(data) = @data = data

            def questions = @data.fetch("questions")

            def pieces = @data.fetch("pieces")

            def asked = @data.fetch("asked")

            def mtime = @data.fetch("mtime")

            def criteria = @data.fetch("criteria")

            # {O<n> => the latest answer sent and no session took}.
            def sent_answers
                @sent_answers ||= unfiled.each_with_object({}) do |entry, out|
                    ref = entry["ref"]
                    out[ref] = entry if ref.to_s.match?(/\AO\d+\z/)
                end
            end

            # {P<n> => the latest word sent on that piece, not filed}.
            def sent_words
                @sent_words ||= unfiled.select { sent_word?(it) }
                                       .to_h { [it["ref"], it] }
            end

            # The pieces that cannot move without the user's word.
            def owed = pieces.reject { it["words"].empty? }

            # When a piece's longest-awaited word was first seen, or "".
            def word_since(piece)
                keys = piece["words"].map { "#{piece["id"]}:#{it.first}" }
                keys.filter_map { asked[it] }.min || ""
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
                live = pieces.reject { DEAD.include?(it["status"]) }
                kept = live.count { it["status"].start_with?("kept:") }
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

            def unfiled = @data.fetch("inbox").reject { it["taken"] }

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

            def unprepared = questions.reject { filled?(it["prep"]) }

            def waiting?
                unprepared.any? { !sent_answers.key?(it["id"]) } ||
                    owed.any? { !sent_words.key?(it["id"]) }
            end

            def answered? = !unprepared.empty? || !owed.empty?

            def flying?
                questions.any? { filled?(it["prep"]) } ||
                    pieces.any? { IN_FLIGHT.include?(it["status"]) }
            end

            # [{word => how many pieces}, [what 'other' needs]].
            def tally_words
                tally = Hash.new(0)
                needs = []
                owed.each do |piece|
                    next if sent_words.key?(piece["id"])

                    piece["words"].each do |word, desc|
                        tally[word] += 1
                        needs << desc if word == "other" && filled?(desc)
                    end
                end
                [tally, needs]
            end
        end
    end
end
