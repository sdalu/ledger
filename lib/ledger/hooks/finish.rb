# frozen_string_literal: true

require "ledger/hooks/ledgers"

module Ledger
    module Hooks
        # Stop: a session whose ledger says the work is over, but whose
        # ledger fails `check --final`, is sent back once to finish
        # against the Goal. It acts only when a ledger has a piece, no
        # piece is planned, out, back or blocked, none awaits the user's
        # word, and no question is open: a turn ending then can only be a
        # finish. On the retry (stop_hook_active) the stop goes through.
        module Finish
            UNSETTLED = %w[planned out back blocked].freeze
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

            # -> the `--final` FAIL lines of a ledger whose work is over.
            def failures(found)
                return [] unless over?(found.derive)
                Checks.run(found.snapshot, final: true)
                      .reject { |_, ok, _| ok }
                      .map do |name, _, detail|
                    detail.empty? ? "FAIL #{name}" : "FAIL #{name} -- #{detail}"
                end
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
