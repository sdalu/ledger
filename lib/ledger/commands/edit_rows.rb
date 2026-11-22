# frozen_string_literal: true

module Ledger
    module Commands
        # What `edit` writes into the row an id names: one method per kind
        # of item whose words it rewords.
        module EditRows
            QUOTE = /["“](.+?)["”]/
            Z = /\AZ([1-9]\d*)\z/
            COLUMN = { "O" => %i[questions detail] }.freeze
            # The item letters whose words another command writes.
            OWN_WRITER = { "P" => "piece PATH P<n> --what",
                           "D" => "criterion PATH D<n> --text" }.freeze
            UNKNOWN = "is not an item edit takes (F, A, C, X, O, Z, goal)"

            private

            def change_item(change, id, words)
                text = words[:text]
                case id
                when /\AF/ then fact(change, id, words)
                when Z then noticed(change, Regexp.last_match(1).to_i, text)
                when /\AA/ then assumption(change, id, text)
                when /\AC/ then constraint(change, id, text)
                when /\AX/ then decision(change, id, text)
                else column(change, id, text)
                end
            end

            def fact(change, id, words)
                change.update(:facts, change.resolve(id).last[:id], **words)
            end

            def noticed(change, id, text)
                row = journal.db[:noticed].where(ledger_id: change.ledger_id,
                                                 id:).first
                refuse("Z#{id} is not this ledger's") unless row
                change.update(:noticed, id, line: "- #{text}")
            end

            def assumption(change, id, text)
                change.update(:assumptions, change.resolve(id).last[:id],
                              text:)
            end

            def constraint(change, id, text)
                quote = text[QUOTE, 1] || text.split(" — ").first
                change.update(:constraints, change.resolve(id).last[:id],
                              text:, quote:)
            end

            def decision(change, id, text)
                row = change.resolve(id).last
                shape = "- #{row[:date]} — #{text} — by #{row[:by]}"
                shape += " (#{row[:note]})" if row[:note]
                refuse("not a decision line: #{shape}") unless
                    Decide::LINE.match?(shape)
                subject = text[Decide::SUBJECT, 1]
                change.update(:decisions, row[:id], body: text, subject:)
            end

            def column(change, id, text)
                table, name = COLUMN.fetch(id[0]) { unedited(id) }
                change.update(table, change.resolve(id).last[:id], name => text)
            end

            def unedited(id)
                writer = OWN_WRITER[id[0]]
                refuse("#{id} has its own writer: #{writer}") if writer
                refuse("#{id} #{UNKNOWN}")
            end
        end
    end
end
