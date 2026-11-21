# frozen_string_literal: true

module Ledger
    module Checks
        # The rules on the assumptions. assumptions-refuted: no piece in
        # flight (planned, out, back, blocked, deferred) and no open
        # question rests on an assumption a fact refuted; the plan built
        # on it is redone or let go. assumptions-settled: an assumption
        # confirmed or refuted names the fact that settled it.
        module Assumptions
            # Their `check --fix-hints` lines, merged into HINTS.
            HINTS = {
                "assumptions-refuted" =>
                    "nothing in flight rests on a refuted assumption; redo " \
                    "the piece or question without it, `bin/ledger assume " \
                    "PATH A<n> --for IDS` to say what still rests on it, or " \
                    "`bin/ledger piece PATH P<n> --status dropped` with a " \
                    "Decision",
                "assumptions-settled" =>
                    "a settled assumption names its fact; `bin/ledger " \
                    "assume PATH A<n> --reopen`, then `--confirmed-by F<n>` " \
                    "or `--refuted-by F<n>`"
            }.freeze

            module_function

            # "P3 rests on A2 (refuted)" for each piece then question, in
            # row order.
            def refuted(derive)
                flight = derive.pieces.select { derive.in_flight?(it) }
                pieces = flight.map do |piece|
                    [derive.ref(piece), derive.rests_on(piece)]
                end
                questions = derive.open_questions.map do |question|
                    [derive.qref(question), derive.question_rests_on(question)]
                end
                (pieces + questions).filter_map { |id, rows| line(id, rows) }
            end

            def line(id, rows)
                bad = rows.select { it[:state] == "refuted" }
                return if bad.empty?

                "#{id} rests on #{bad.map { "A#{it[:n]}" }.join(", ")} " \
                    "(refuted)"
            end

            # "A2 confirmed without its fact" for each one settled by no
            # fact.
            def settled(derive)
                derive.assumptions.filter_map do |row|
                    next if row[:state] == "open" || row[:fact_id]

                    "#{derive.aref(row)} #{row[:state]} without its fact"
                end
            end
        end
    end
end
