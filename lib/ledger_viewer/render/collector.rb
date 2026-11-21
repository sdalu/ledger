# frozen_string_literal: true

require_relative "helpers"
require_relative "reading"
require_relative "table"
require_relative "text"

module LedgerViewer
    module Render
        # What the index gathers from the ledgers, one at a time: the
        # queue of what waits on the user (each with its sort key), the
        # sessions' turn, the table rows and the counts of the summary.
        class Collector
            # The queue: [group, since, updated, order, html]; the rows are
            # [sort key, html].
            attr_reader :queue, :theirs, :rows, :totals

            def initialize(scope)
                @scope = scope
                @table = Table.new(scope)
                @queue = []
                @theirs = []
                @rows = []
                @totals = Hash.new(0)
            end

            def add(entry, data)
                name = Helpers.project_name(entry.project, entry.path)
                reading = Reading.new(data)
                questions(entry.id, name, reading)
                owed(entry.id, name, reading)
                @rows << @table.row(entry.id, name, reading)
            end

            private

            def questions(lid, name, reading)
                reading.questions.each do |q|
                    if q["preparing"] then prepared(lid, name, q)
                    elsif (sent = reading.sent_answers[q["id"]])
                        filed(lid, name, q, "q", sent)
                    else ask(lid, name, reading, q)
                    end
                end
            end

            def prepared(lid, name, q)
                @totals[:prepared] += 1
                @theirs << @scope.partial(
                    "index/prepared",
                    lid:, name:, id: q["id"], title: q["title"],
                    prep: q["preparing"],
                    status: q["preparing_status"]
                )
            end

            def filed(lid, name, item, kind, entry)
                @totals[:sent] += 1
                summary = Helpers.answer_summary(entry)
                id = item["id"]
                @theirs << @scope.partial("index/sent",
                                          lid:, name:, id:, summary:,
                                          title: item["title"],
                                          anchor: "#{kind}-#{id}")
            end

            def ask(lid, name, reading, q)
                @totals[:asks] += 1
                since = reading.asked.fetch(q["id"], "")
                risk = Text.risk_clause(q["risk"]&.fetch("text").to_s)
                queued(reading, since,
                       id: q["id"], lid:, name:, risk:, title: q["title"],
                       what: "question", label: "Answer",
                       anchor: "q-#{q["id"]}")
            end

            def owed(lid, name, reading)
                reading.owed.each do |piece|
                    entry = reading.sent_words[piece["id"]]
                    next filed(lid, name, piece, "p", entry) if entry

                    @totals[:words] += 1
                    ask_word(lid, name, reading, piece)
                end
            end

            def ask_word(lid, name, reading, piece)
                words = Reading.words(piece)
                risk = Text.risk_clause(piece["risk"]&.fetch("text").to_s)
                queued(reading, reading.word_since(piece),
                       lid:, name:, risk:, id: piece["id"],
                       title: piece["title"],
                       anchor: "p-#{piece["id"]}",
                       what: "awaits #{Helpers.bare_label(words)}",
                       label: Helpers.answer_label(words))
            end

            def queued(reading, since, **locals)
                wait = Ledger::Text.waited(since)
                html = @scope.partial("index/ask", wait:, **locals)
                @queue << [*WaitingOrder.key(since), reading.updated,
                           @queue.length, html]
            end
        end
    end
end
