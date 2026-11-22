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

            # 'serves D2', 'prepares O3': what a piece's RAID line says of
            # the criteria and questions around it; the pieces it waits
            # for and serves are its ties' (Ties).
            def forward(piece, reading)
                [("serves #{ids(piece["for"], "crit")}" if
                     piece["for"].any?),
                 prepares(piece["id"], reading.questions)].compact
            end

            # The meta, evidence and done fields of a piece's row: what it
            # waits for is its ties line (Ties), what it serves its RAID
            # line (Raid).
            def fields(piece)
                { meta: piece["route_text"].to_s,
                  evidence: piece["evidence"].to_s,
                  done: piece["done_when"].to_s }
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
