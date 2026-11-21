# frozen_string_literal: true

module Ledger
    module Render
        # The visible id of a row another row points at: a foreign key
        # holds a row id, the Markdown names the item by its kind letter
        # and its n.
        class Refs
            TABLES = { "P" => :pieces, "D" => :criteria,
                       "C" => :constraints, "F" => :facts }.freeze

            # The rows of a child table by the row that owns them, each
            # list in line order: the column `position`, then the row id.
            def self.group(rows, owner)
                rows.group_by { it[owner] }.transform_values do |list|
                    list.sort_by { |row| [row[:position].to_i, row[:id]] }
                end
            end

            # " — prose" from the prose stored after a link's ids, which
            # may or may not carry its dash; "" for none.
            def self.tail(text)
                return "" if text.nil? || text.empty?

                text.start_with?(" — ") ? text : " — #{text}"
            end

            def initialize(snapshot)
                @numbers = TABLES.transform_values do |table|
                    snapshot[table].to_h { [it[:id], it[:n]] }
                end
            end

            # ("P", 3) -> "P7", when row 3 of pieces has n 7.
            def [](kind, row_id)
                "#{kind}#{@numbers.fetch(kind).fetch(row_id)}"
            end
        end
    end
end
