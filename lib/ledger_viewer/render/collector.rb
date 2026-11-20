# frozen_string_literal: true

require_relative "helpers"
require_relative "reading"
require_relative "table"
require_relative "text"

module LedgerViewer
    module Render
        # What the index gathers from the ledgers, one at a time, as
        # render_index() does in its loop: the queue of what waits on the
        # user (each with its sort key), the sessions' turn, the table
        # rows, the open lines with no id, and the counts of the summary.
        class Collector
            # The queue: [group, since, mtime, order, html]; the rest are
            # [sort key, html].
            attr_reader :queue, :theirs, :rows, :noid, :totals

            def initialize(scope)
                @scope = scope
                @table = Table.new(scope)
                @queue = []
                @theirs = []
                @rows = []
                @noid = []
                @totals = Hash.new(0)
            end

            def add(entry, data)
                name = Helpers.project_name(entry.project, entry.path)
                @rows << row(entry.id, name, data)
            end

            private

            def row(lid, name, data)
                return @table.unreadable(lid, name) unless data

                read(lid, name, Reading.new(data))
            end

            def read(lid, name, reading)
                unnamed = questions(lid, name, reading)
                owed(lid, name, reading)
                loose(lid, name, reading.mtime, unnamed)
                @table.row(lid, name, reading)
            end

            def questions(lid, name, reading)
                unnamed = 0
                reading.questions.each do |q|
                    if Helpers.filled?(q["prep"]) then prepared(lid, name, q)
                    elsif q["id"].nil? then unnamed += 1
                    elsif (sent = reading.sent_answers[q["id"]])
                        filed(lid, name, q["id"], "q", sent)
                    else ask(lid, name, reading, q)
                    end
                end
                unnamed
            end

            def prepared(lid, name, q)
                @totals[:prepared] += 1
                id = q["id"]
                @theirs << @scope.partial("index/prepared",
                                          lid:, name:, id:, prep: q["prep"],
                                          status: q["prep_status"])
            end

            def filed(lid, name, id, kind, entry)
                @totals[:sent] += 1
                summary = Helpers.answer_summary(entry)
                @theirs << @scope.partial("index/sent",
                                          lid:, name:, id:, summary:,
                                          anchor: "#{kind}-#{id}")
            end

            def ask(lid, name, reading, q)
                @totals[:asks] += 1
                since = reading.asked.fetch(q["id"], "")
                text = Text.question_text(q["text"])
                risk = Text.risk_clause(Text.case_of(q["text"])["risk"].to_s)
                title = Text.title_of(text).first
                queued(reading, since,
                       id: q["id"], lid:, name:, risk:, title:,
                       what: "question", label: "Answer",
                       anchor: "q-#{q["id"]}")
            end

            def owed(lid, name, reading)
                reading.owed.each do |piece|
                    entry = reading.sent_words[piece["id"]]
                    next filed(lid, name, piece["id"], "p", entry) if entry

                    @totals[:words] += 1
                    ask_word(lid, name, reading, piece)
                end
            end

            def ask_word(lid, name, reading, piece)
                words = piece["words"]
                risk = Text.risk_clause(piece.fetch("risk", ""))
                title = Text.title_of(piece["what"]).first
                queued(reading, reading.word_since(piece),
                       lid:, name:, risk:, id: piece["id"], title:,
                       anchor: "p-#{piece["id"]}",
                       what: "awaits #{Helpers.bare_label(words)}",
                       label: Helpers.answer_label(words))
            end

            def queued(reading, since, **locals)
                wait = Text.waited(since)
                html = @scope.partial("index/ask", wait:, **locals)
                @queue << [since.empty? ? 1 : 0, since, reading.mtime,
                           @queue.length, html]
            end

            def loose(lid, name, mtime, unnamed)
                return if unnamed.zero?

                plural = Helpers.plural(unnamed)
                html = @scope.partial("index/noid",
                                      lid:, name:, plural:, count: unnamed)
                @noid << [mtime, html]
            end
        end
    end
end
