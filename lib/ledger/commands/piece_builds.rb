# frozen_string_literal: true

module Ledger
    module Commands
        # The rows a piece names beside its own: `--builds O<n>`, the open
        # question it builds (one piece at most per question, `none`
        # clears it), and `--status obsolete --obsoleted-by P<n>`, the
        # piece that replaces it. Resolved inside the write, so a refusal
        # leaves nothing written; any other status clears obsoleted_by.
        class PieceBuilds
            QUESTION = /\AO[1-9]\d*\z/
            PIECE = /\AP[1-9]\d*\z/
            # What a replacement may not be.
            ENDED = %w[obsolete dropped].freeze

            def initialize(change, db, old, opts)
                @change = change
                @db = db
                @old = old
                @opts = opts
            end

            # The columns the flags given set: builds_id, obsoleted_by_id.
            def columns
                out = {}
                out[:builds_id] = builds if @opts.key?("builds")
                out[:obsoleted_by_id] = obsoleted_by if @opts.key?("status")
                out
            end

            private

            def builds
                value = @opts["builds"].strip
                return if value == "none"

                fail!("--builds takes O<n> or none, not #{value}") unless
                    QUESTION.match?(value)
                question = open_question(value)
                taken!(value, question)
                question[:id]
            end

            def open_question(value)
                question = find(value, "Open")
                return question unless question[:closed_at]

                fail!("#{value} is answered: --builds names an open question")
            end

            # One piece builds a question: another one already doing so
            # is refused, not moved.
            def taken!(value, question)
                others = @db[:pieces].where(builds_id: question[:id])
                others = others.exclude(id: @old[:id]) if @old
                n = others.get(:n) or return

                fail!("#{value} is built by P#{n}: one piece builds a " \
                      "question")
            end

            def obsoleted_by
                return unless @opts["status"].strip == "obsolete"

                if @old && @old[:status] == "out"
                    fail!("P#{@old[:n]} is out: a piece out is not made " \
                          "obsolete")
                end
                replacement[:id]
            end

            def replacement
                value = @opts["obsoleted-by"].strip
                fail!("--obsoleted-by takes P<n>, not #{value}") unless
                    PIECE.match?(value)
                piece = find(value, "Pieces")
                fail!("#{value} cannot replace itself") if piece[:id] ==
                                                           @old&.fetch(:id)
                return piece unless ENDED.include?(piece[:status])

                fail!("#{value} is #{piece[:status]}: it replaces nothing")
            end

            def find(ref, section)
                @change.resolve(ref).last
            rescue Unknown
                fail!("no #{ref} under #{section}")
            end

            def fail!(message) = raise(Refused, message)
        end
    end
end
