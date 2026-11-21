# frozen_string_literal: true

require_relative "raid"
require_relative "raid_depends"

module LedgerViewer
    module Render
        # The Assumptions list of the RAID fold: the open assumptions
        # first, then the confirmed and the refuted, each with its check,
        # what it rests on, what rests on it and the fact that settled it;
        # then the decisions by me, the session's reviewable judgements,
        # each with what it rests on.
        class RaidAssumptions
            def initialize(scope, reading)
                @scope = scope
                @reading = reading
            end

            def rows
                ordered = @reading.assumptions.sort_by.with_index do |row, at|
                    [Raid::STATES.index(row["state"]), at]
                end
                ordered.map { assumption(it) } + judgements
            end

            private

            # Its chip and state, its text, then a line per note.
            def assumption(row)
                state = row["state"]
                text = @scope.inline(row["text"])
                head = "<span class=\"tag status\">#{state}</span> " \
                       "<span class=\"text\">#{text}</span>"
                item(row["id"], head, notes(row), cls: "is-#{state}",
                                                  anchor: "raid-#{row["id"]}")
            end

            def notes(row)
                rests = row["for"].map { RaidDepends.link(it) }.join(", ")
                ["check: #{row["check"]}",
                 ("rests on: #{row["see"].join(", ")}" if row["see"].any?),
                 ("for: #{rests}" unless rests.empty?),
                 ("by: #{row["fact"]}" if row["fact"])].compact
            end

            # The decisions by me, each with the facts and constraints it
            # rests on.
            def judgements
                mine = @reading.decision_rows.select { it["by"] == "me" }
                mine.map do |row|
                    rests = rests_on(row["id"])
                    item(row["id"], judgement(row),
                         rests.empty? ? [] : ["rests on: #{rests.join(", ")}"])
                end
            end

            def judgement(row)
                text = @scope.inline(row["body"])
                "<span class=\"tag status\">by me</span> " \
                    "<span class=\"text\">#{text}</span>"
            end

            def rests_on(id)
                links = @reading.links.select do |link|
                    link["kind"] == "rests_on" && link["from"] == id
                end
                links.map { it["to"] }
            end

            def item(id, head, notes, cls: "", anchor: "")
                attr = anchor.empty? ? "" : %( id="#{anchor}")
                meta = notes.map do |note|
                    %(<div class="meta">#{@scope.inline(note)}</div>)
                end
                %(<li class="#{cls}"#{attr}>#{@scope.chip(id)} #{head}) +
                    "#{meta.join}</li>"
            end
        end
    end
end
