# frozen_string_literal: true

require_relative "terms"

module LedgerViewer
    module Render
        # What a piece waits for and serves, said as Markdown links to
        # the cards and criteria on the page.
        module Links
            module_function

            # 'P3, P5' as links to their cards: `piece-P3`, `crit-D2`.
            def ids(ids, kind)
                ids.map { "[#{it}](##{kind}-#{it})" }.join(", ")
            end

            # 'needed by P5, P10': the pieces not settled whose after names
            # ID, in row order; nil when none.
            def needed_by(id, pieces)
                ids = pieces.filter_map do |piece|
                    piece["id"] if piece["after"].include?(id) &&
                                   !piece["settled"]
                end
                "needed by #{ids(ids, "piece")}" if ids.any?
            end

            # 'prepares O3': the open questions whose by names ID; nil when
            # none.
            def prepares(id, questions)
                ids = questions.select { it["by"] == id }.map { it["id"] }
                "prepares #{ids(ids, "q")}" if ids.any?
            end

            # 'decided in X2, X5': the decisions with a led_to link to ID,
            # each to its row in the record; nil when none. Only led_to
            # edges name a piece or a question: rests_on ends at a fact or
            # a constraint, and a piece's --by is a led_to edge.
            def decided(id, reading)
                rows = reading.decision_ids
                said = reading.links.filter_map do |link|
                    next unless link["kind"] == "led_to" && link["to"] == id

                    at = rows.index(link["from"]) and
                        "[#{link["from"]}](#dec-#{at})"
                end
                "decided in #{said.uniq.join(", ")}" if said.any?
            end

            # 'waiting 3 h' once a question has waited over an hour; nil
            # before that.
            def waiting(question)
                since = question["asked_since"]
                at = Ledger::Text.local_time(since)
                return unless at && Time.now - at > 3600

                "waiting #{Age.of(Ledger::Text.waited(since))}"
            end

            # 'answered by P5' while that piece is not settled and not
            # stalled, which the issues part says instead; nil otherwise.
            def answering(question, pieces)
                by = pieces.find { it["id"] == question["by"] }
                return if by.nil? || by["settled"] || by["stalled"]

                "answered by #{ids([by["id"]], "piece")}"
            end

            # The issues of an open question as one line: how long it has
            # waited, its answering piece stalled (the text STALLED says of
            # that piece); "" when it has none.
            def question_issues(question, pieces, stalled)
                by = pieces.find { it["id"] == question["by"] }
                said = [waiting(question)]
                if by&.dig("stalled")
                    said << "answered by #{ids([by["id"]], "piece")}, " \
                            "#{stalled.call(by)}"
                end
                said.compact.join(" · ")
            end

            # 'waits for P3' (or its after pieces settled), 'serves D2',
            # 'needed by P5, P10', 'prepares O3': what a piece's RAID line
            # says of the pieces and questions around it.
            def forward(piece, reading)
                [(waits(piece, reading.settled) if piece["after"].any?),
                 ("serves #{ids(piece["for"], "crit")}" if
                     piece["for"].any?),
                 needed_by(piece["id"], reading.pieces),
                 prepares(piece["id"], reading.questions)].compact
            end

            # The meta, evidence and done fields of a piece's row: what it
            # waits for and serves is its RAID line's (Raid).
            def fields(piece)
                { meta: piece["route_text"].to_s,
                  evidence: piece["evidence"].to_s,
                  done: piece["done_when"].to_s }
            end

            # 'waits for P3' while an after piece is not settled; `settled`
            # is {id => whether that piece is settled}.
            def waits(piece, settled)
                after = piece["after"]
                waiting = after.reject { settled.fetch(it, false) }
                return "waits for #{ids(waiting, "piece")}" unless
                    waiting.empty?

                ready = piece["status"] == "planned" ? "ready: " : ""
                "#{ready}after #{ids(after, "piece")}, settled"
            end

            # ['verified', 'kept'] -> '2 pieces: 1 verified, 1 kept': the
            # verified and the kept first, every other status after, in the
            # order seen.
            def counts(statuses)
                tally = statuses.tally
                keys = tally.keys.sort_by.with_index do |key, at|
                    [key == "verified" ? 0 : 1, key == "kept" ? 0 : 1, at]
                end
                total = statuses.length
                "#{total} piece#{"s" unless total == 1}: " +
                    keys.map { "#{tally[it]} #{it}" }.join(", ")
            end
        end
    end
end
