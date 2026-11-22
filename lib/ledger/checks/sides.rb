# frozen_string_literal: true

require "ledger/text/awaits"

module Ledger
    module Checks
        # pictures: a piece awaiting commit, deploy, push or merge shows
        # the user what the word changes, a before and an after placed
        # (`mockup --piece`), or says why it needs none (`piece
        # --no-picture`). start and other are exempt; a word once given
        # leaves with its awaits row.
        module Sides
            # Their `check --fix-hints` lines, merged into HINTS.
            HINTS = {
                "pictures" =>
                    "a piece awaiting commit, deploy, push or merge shows " \
                    "what it changes, a before and an after; `bin/ledger " \
                    "mockup PATH FILE --piece P<n> --before` and `--after`, " \
                    "or `bin/ledger piece PATH P<n> --no-picture WHY`"
            }.freeze

            ROLES = %w[before after].freeze

            module_function

            # "P3 (awaits commit; has before)" for each piece lacking.
            def problems(derive)
                derive.pieces.filter_map { problem(derive, it) }
            end

            def problem(derive, piece)
                words = finishing(derive, piece)
                return if words.empty? || derive.present?(piece[:no_picture])

                placed = derive.pictures(piece).map { it[:role] }.uniq
                return if (ROLES - placed).empty?

                has = "; has #{placed.join(", ")}" if placed.any?
                "#{derive.ref(piece)} (awaits #{words.join(", ")}#{has})"
            end

            # The commit, deploy, push and merge the piece awaits.
            def finishing(derive, piece)
                derive.awaits(piece).map(&:first)
                      .select { Text::Awaits.finish?(it) }
            end
        end
    end
end
