# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # What a piece's status means, and how its tag says it.
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

            # The tag: the status, a kept piece's reason after it.
            def of(piece)
                status = piece["status"]
                status == "kept" ? "kept: #{piece["kept_reason"]}" : status
            end

            # 'verified: checked against ...', or "" for a status that
            # has no tip.
            def tip(piece)
                status = piece["status"]
                if status == "kept"
                    "kept: done by the session itself " \
                        "(#{Text.strip(piece["kept_reason"])})"
                elsif MEANING.key?(status)
                    "#{status}: #{MEANING[status]}"
                else
                    ""
                end
            end
        end
    end
end
