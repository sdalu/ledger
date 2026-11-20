# frozen_string_literal: true

require_relative "terms"
require_relative "text"

module LedgerViewer
    module Render
        # What a piece's status means, from ledger.py's own list:
        # status_tip() of ledger-serve.py.
        module Status
            MEANING = {
                "planned" => "briefed or to be briefed, not sent",
                "out" => "with a delegate or peer",
                "back" => "returned, not verified yet",
                "verified" => "checked against its done when, the " \
                              "evidence on the line",
                "blocked" => "stopped on a question, named under Open or " \
                             "on the line",
                "dropped" => "abandoned, the reason in a Decision"
            }.freeze

            module_function

            # 'verified: checked against ...', or "" for a status that
            # has no tip.
            def tip(status)
                if Terms.kept?(status)
                    "kept: done by the session itself " \
                        "(#{Text.strip(status[5..])})"
                elsif MEANING.key?(status)
                    "#{status}: #{MEANING[status]}"
                else
                    ""
                end
            end
        end
    end
end
