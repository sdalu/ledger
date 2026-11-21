# frozen_string_literal: true

require_relative "entry"
require_relative "reading"
require_relative "sectioned"
require_relative "serving"

module LedgerViewer
    module Render
        # The criteria not met yet, read with the goal they measure: the
        # page draws them straight under the Goal.
        class Unmet
            include Sectioned

            ALL_MARKED = "Every criterion is marked."
            EVIDENCE = / — evidence:\z/

            def initialize(kit)
                @scope = kit.scope
                @reading = kit.reading
                @entry = Entry.new(@scope)
                @serving = Serving.new(@scope, @reading)
            end

            def html
                section("Criteria not met yet", rows, "criteria",
                        empty: ALL_MARKED)
            end

            private

            # The fold's summary says "evidence from", so the criterion's
            # own empty marker goes.
            def rows
                @reading.unmet.map do |criterion|
                    meta, fold = @serving.of(criterion)
                    text = Reading.criterion(criterion)
                    text = text.sub(EVIDENCE, "") unless fold.empty?
                    @entry.html(cls: "is-flight", tag: criterion["id"], text:,
                                meta:, fold:, anchor: "crit-#{criterion["id"]}")
                end
            end
        end
    end
end
