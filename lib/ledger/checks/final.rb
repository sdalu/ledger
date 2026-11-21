# frozen_string_literal: true

module Ledger
    module Checks
        # The rules of `check --final`: what `close` and the proposal to
        # close ask of a finished ledger.
        module Final
            module_function

            # Each piece planned, out or back.
            def pieces(derive)
                derive.pieces.select { derive.unfinished?(it) }.map do |piece|
                    "#{derive.ref(piece)} [#{piece[:status]}]"
                end
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
