# frozen_string_literal: true

module Ledger
    module Checks
        # The rules of `check --final`: what `close` and the proposal to
        # close ask of a finished ledger.
        module Final
            # Their `check --fix-hints` lines, merged into HINTS.
            HINTS = {
                "final-pieces" =>
                    "no piece planned, out or back; `bin/ledger piece PATH " \
                    "P<n> " \
                    "--status verified --verified-by me --evidence …` or " \
                    "`--status dropped` with a Decision",
                "final-deferred" =>
                    "no piece deferred: the ledger waits for its event; once " \
                    "it came, `bin/ledger piece PATH P<n> --status planned`, " \
                    "or `--status dropped` with a Decision; meanwhile the " \
                    "stop " \
                    "passes, criteria unmarked too if each waits on deferred " \
                    "pieces only or on no piece",
                "final-awaits" =>
                    "no piece waits for the user's word; `bin/ledger word " \
                    "PATH " \
                    "P<n> --word W` once given, or `--word drop`",
                "final-criteria" =>
                    "every criterion `[x]` with evidence or `[-]` with why; " \
                    "`bin/ledger criterion PATH D<n> --met EVIDENCE` or " \
                    "`--unmet WHY`"
            }.freeze

            module_function

            # Each piece planned, out or back; a deferred one is said by
            # `deferred`, with its condition.
            def pieces(derive)
                open = derive.pieces.select { derive.unfinished?(it) }
                open.reject { it[:status] == "deferred" }.map do |piece|
                    "#{derive.ref(piece)} [#{piece[:status]}]"
                end
            end

            # Each piece deferred, as `P6 (CONDITION)`.
            def deferred(derive)
                derive.deferred.map { derive.deferral(it) }
            end

            # Each piece still awaiting the user's word.
            def awaits(derive)
                derive.pieces.filter_map do |piece|
                    next if derive.awaits(piece).empty?
                    "#{derive.ref(piece)} (#{derive.awaits_label(piece)})"
                end
            end

            # Each criterion unmarked, met without evidence, or not met
            # without why; a ledger without criteria fails too.
            def criteria(derive)
                return [""] if derive.criteria.empty?
                derive.criteria.filter_map { problem(derive, it) }
            end

            def problem(derive, criterion)
                id = "D#{criterion[:n]}"
                case criterion[:mark]
                when " " then "#{id} unmarked"
                when "x"
                    "#{id} met without evidence" \
                        unless derive.present?(criterion[:evidence])
                else
                    "#{id} not met without why:" \
                        unless derive.present?(criterion[:why])
                end
            end
        end
    end
end
