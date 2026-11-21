# frozen_string_literal: true

require_relative "links"
require_relative "reading"

module LedgerViewer
    module Render
        # The Dependencies of the RAID fold, as [id, Markdown] pairs: each
        # after link of a piece in flight whose piece is not settled, each
        # question's by piece not settled, each deferred condition.
        module RaidDepends
            module_function

            def of(reading)
                afters(reading) + bys(reading) + deferred(reading)
            end

            # The pieces in flight, in row order.
            def flight(reading)
                reading.pieces.select do |piece|
                    Reading::IN_FLIGHT.include?(piece["status"])
                end
            end

            # '[P3](#piece-P3)', '[O1](#q-O1)'.
            def link(id) = Links.ids([id], id.start_with?("O") ? "q" : "piece")

            def afters(reading)
                flight(reading).flat_map do |piece|
                    waiting = piece["after"].reject { reading.settled[it] }
                    waiting.map { [piece["id"], "waits for #{link(it)}"] }
                end
            end

            def bys(reading)
                reading.questions.filter_map do |question|
                    by = question["by"]
                    next if by.nil? || reading.settled[by]

                    [question["id"], "answered by #{link(by)}"]
                end
            end

            def deferred(reading)
                flight(reading).select { it["status"] == "deferred" }
                               .map { [it["id"], "until #{it["until"]}"] }
            end
        end
    end
end
