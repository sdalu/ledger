# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # What the helper of a piece out or back says of its work: its
        # gates as chips, 'NAME passed', coloured by state, the time of
        # the state on hover; the DETAIL of the last gate that failed
        # under them; and its report folded, 'Report: STATUS' its
        # summary. Once the piece is verified, or in any status but out
        # and back, nothing is drawn: show keeps both.
        class Gates
            SHOWN = %w[out back].freeze

            def initialize(scope) = @scope = scope

            def html(piece)
                return "" unless SHOWN.include?(piece["status"])

                gates = piece.fetch("gates", [])
                chips(gates) + failure(gates) + report(piece["report"])
            end

            private

            def chips(gates)
                return "" if gates.empty?

                items = gates.map { chip(it) }.join
                %(<ul class="gates" aria-label="Gates">#{items}</ul>)
            end

            def chip(gate)
                state = gate["state"]
                attrs, box = @scope.tip("#{state} #{Text.minute(gate["at"])}")
                %(<li><span class="gate is-#{state}" tabindex="0"#{attrs}>) +
                    "#{Text.escape(gate["name"])} #{state}</span>#{box}</li>"
            end

            # The last failure said, when it says why; of two at one time,
            # the one recorded later.
            def failure(gates)
                failed = gates.select { it["state"] == "failed" }.reverse
                last = failed.max_by { it["at"].to_s } or return ""
                return "" if last["detail"].to_s.empty?

                %(<p class="gate-failure">#{Text.escape(last["name"])}: ) +
                    "#{@scope.inline(last["detail"])}</p>"
            end

            def report(report)
                return "" unless report

                lines = report["lines"].map { Text.escape(it) }.join("\n")
                summary = "<summary>Report: " \
                          "#{Text.escape(report["status"])}</summary>"
                body = %(<div class="report-lines">#{lines}</div>)
                %(<details class="report">#{summary}#{body}</details>)
            end
        end
    end
end
