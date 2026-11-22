# frozen_string_literal: true

require "json"

require "ledger/text/awaits"

module Ledger
    module Commands
        # Once the user's word on a piece is pending or given, `piece`
        # leaves its --scope, --problem and --plan as they are: the word
        # was given for what the piece said, and a wider change is a new
        # piece. A new --awaits (the piece put to a new word) lifts it,
        # in that same write and after it until the next word.
        class PieceWordScope
            # The flag of each field and how its stored value is read.
            FIELDS = %w[scope problem plan].freeze
            MESSAGE = "word-scope: the word was given for what the piece " \
                      "said; a wider change is a new piece (--awaits puts " \
                      "it to a new word)"

            def initialize(change, db, old, opts)
                @change = change
                @db = db
                @old = old
                @opts = opts
            end

            # Refuses the write when it changes a field the word covers.
            # STORED_AWAITS and AWAITS are the [[word, what]] lists before
            # and after the write, STORED_SCOPES the stored [[word, text]].
            def check(stored_awaits, awaits, stored_scopes)
                return unless @old
                return if awaits.any? && awaits != stored_awaits

                changed = FIELDS.select { changes?(it, stored_scopes) }
                return if changed.empty? || !word?

                raise Refused.new("#{MESSAGE}: --#{changed.join(", --")}",
                                  rule: "word-scope")
            end

            private

            def changes?(field, stored_scopes)
                return false unless @opts.key?(field)

                field == "scope" ? scope_changes?(stored_scopes) : prose?(field)
            end

            # A first fill, or the same value again, is no change.
            def prose?(field)
                stored = @old[field.to_sym].to_s
                given = @opts[field].strip
                !stored.empty? && given != stored
            end

            def scope_changes?(stored)
                value = @opts["scope"].strip
                given = value.empty? ? [] : Text::Awaits.scope_words(value)
                stored.any? && given != stored
            end

            def word? = pending? || given?

            # An entry of the viewer carrying a word on the piece, not
            # yet taken.
            def pending?
                @db[:inbox_entries].where(ledger_id: @change.ledger_id,
                                          ref: "P#{@old[:n]}", taken_id: nil,
                                          malformed: false)
                                   .select_map(:payload)
                                   .any? { word_entry?(it) }
            end

            def word_entry?(payload)
                word = JSON.parse(payload)["word"]
                word.is_a?(String) && !word.strip.empty?
            rescue JSON::ParserError, TypeError
                false
            end

            # A `word` event led a decision to the piece after its latest
            # awaits write, and no undo took it back.
            def given?
                since = asked_event
                words.where { Sequel[:events][:id] > since }
                     .exclude(Sequel[:events][:id] => undone).any?
            end

            def words
                @db[:links].join(:events, id: :event_id)
                           .where(Sequel[:links][:kind] => "led_to",
                                  to_kind: "P", to_row: @old[:id],
                                  Sequel[:events][:command] => "word")
            end

            def undone = @db[:events].exclude(undoes: nil).select(:undoes)

            # The newest event that wrote one of the piece's awaits rows.
            def asked_event
                owner = Sequel.lit("json_extract(after, '$.piece_id')")
                @db[:event_rows].where(tbl: "piece_awaits", before: nil)
                                .where(owner => @old[:id])
                                .max(:event_id) || 0
            end
        end
    end
end
