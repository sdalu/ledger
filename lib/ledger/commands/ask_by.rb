# frozen_string_literal: true

module Ledger
    module Commands
        # The `--by` link of a question: the piece named, resolved for a
        # new question, and `ask PATH O<n> --by P<n>|none`, which sets,
        # changes or clears it on an open one.
        class AskBy
            # The question text `ask` reads as an existing question.
            QUESTION = /\AO[1-9]\d*\z/

            def self.question?(text) = QUESTION.match?(text.strip)

            # The row id of the piece REF names, which must not be dropped.
            def self.piece(change, ref)
                raise Refused, "--by names a piece, P<n>" unless
                    ref.match?(/\AP[1-9]\d*\z/)

                row = change.resolve(ref).last
                if row[:status] == "dropped"
                    raise Refused, "--by #{ref}: that piece is dropped and " \
                                   "will prepare nothing"
                end
                row[:id]
            end

            def initialize(change, opts)
                @change = change
                @opts = opts
            end

            # -> the question's visible id once its link is written.
            def relink(ref)
                value = @opts["by"]&.strip or
                    refuse("#{ref} is changed by --by P<n> or --by none")
                other = @opts.keys.grep(String) - %w[by]
                refuse("#{ref} takes only --by, not --#{other.first}") if
                    other.any?
                row = open_question(ref)
                by_id = value == "none" ? nil : self.class.piece(@change, value)
                @change.own = ref
                @change.update(:questions, row[:id], by_id:)
                ref
            end

            private

            def refuse(message) = raise(Refused, message)

            def open_question(ref)
                row = @change.resolve(ref).last
                refuse("#{ref} is not asked under Open") if row[:closed_at]
                row
            end
        end
    end
end
