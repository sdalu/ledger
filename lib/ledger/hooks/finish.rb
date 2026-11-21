# frozen_string_literal: true

require "ledger/hooks/ledgers"

module Ledger
    module Hooks
        # Stop: a session whose ledger says the work is over, but whose
        # ledger fails `check --final`, is sent back once to finish
        # against the Goal. It acts only when a ledger has a piece, no
        # piece is planned, out, back or blocked, none awaits the user's
        # word, and no question is open: a turn ending then can only be a
        # finish. A ledger that fails only on its pieces deferred until
        # an event lets the stop through: the session waits on that
        # event, as it would on the user. So does one that fails besides
        # only on criteria unmarked, each served by deferred pieces among
        # its unfinished ones or by no piece at all: they wait on the same
        # event. On the retry (stop_hook_active) the stop goes through.
        module Finish
            UNSETTLED = %w[planned out back blocked].freeze
            # The --final rule a ledger may fail alone and still stop.
            WAITING = "final-deferred"
            # The rules a ledger may fail beside it, on criteria waiting.
            EXEMPT = [WAITING, "final-criteria"].freeze
            STEPS = "Before reporting done (orchestration, Finish): re-read " \
                    "the Goal, every revision, and Done when; check each " \
                    "criterion against the artifact, not the reports, and " \
                    "mark it with `bin/ledger criterion ADDRESS D<n> --met " \
                    "EVIDENCE` or `--unmet WHY`; then run `bin/ledger check " \
                    "--final ADDRESS` until it prints no FAIL. If you are " \
                    "not finishing -- waiting on the user or on a piece -- " \
                    "say so in the ledger (the question under Open, the " \
                    "piece's status) and stop again."

            module_function

            def call(payload)
                return Answer.pass if payload["stop_hook_active"]
                lines = Ledgers.read(payload).flat_map do |found|
                    failures(found).map { "#{found.address}: #{it}" }
                end
                return Answer.pass if lines.empty?
                Answer.refuse([STEPS, *lines].join("\n"))
            end

            # -> the `--final` FAIL lines of a ledger whose work is over;
            # none when deferred pieces are all it fails on.
            def failures(found)
                return [] unless over?(found.derive)
                failed = Checks.run(found.snapshot, final: true)
                               .reject { |_, ok, _| ok }
                return [] if waiting?(found.derive, failed.map(&:first))
                failed.map do |name, _, detail|
                    detail.empty? ? "FAIL #{name}" : "FAIL #{name} -- #{detail}"
                end
            end

            # Deferred pieces failing, alone or with criteria that wait on
            # them.
            def waiting?(derive, names)
                return false unless names.include?(WAITING)
                return true if names.all? { it == WAITING }
                (names - EXEMPT).empty? && criteria_wait?(derive)
            end

            # Each criterion --final names is unmarked and waits: on
            # deferred pieces only among its unfinished ones, or on none.
            def criteria_wait?(derive)
                named = derive.criteria.select do |criterion|
                    Checks::Final.problem(derive, criterion)
                end
                named.any? && named.all? do |row|
                    row[:mark] == " " && served_waiting?(derive, row)
                end
            end

            def served_waiting?(derive, criterion)
                serving = derive.pieces.select do |piece|
                    derive.serves(piece).any? { it[:id] == criterion[:id] }
                end
                open = serving.select { derive.unfinished?(it) }
                return serving.empty? if open.empty?
                open.all? { it[:status] == "deferred" }
            end

            def over?(derive)
                pieces = derive.pieces
                pieces.any? && derive.open_questions.empty? &&
                    pieces.none? { UNSETTLED.include?(it[:status]) } &&
                    pieces.all? { derive.awaits(it).empty? }
            end
        end
    end
end
