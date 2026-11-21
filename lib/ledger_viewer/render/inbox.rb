# frozen_string_literal: true

require_relative "clock"
require_relative "helpers"
require_relative "terms"
require_relative "text"

module LedgerViewer
    module Render
        # Your messages: everything sent from the viewer, newest first,
        # what the session has not taken above and what it has folded
        # below.
        class Inbox
            KINDS = { "answer" => "answer to %<ref>s",
                      "comment" => "comment on piece %<ref>s",
                      "ask" => "comment on question %<ref>s, not an answer",
                      "word" => "word on %<ref>s",
                      "order" => "proposed order of the planned pieces",
                      "note" => "note" }.freeze

            def initialize(kit)
                @scope = kit.scope
                @reading = kit.reading
                @lid = kit.lid
                @blocks = kit.blocks
            end

            def html
                said, filed = @reading.inbox.reverse.partition { !it["taken"] }
                said = said.map { row(it) }
                filed = filed.map { row(it) }
                @scope.partial("ledger/inbox",
                               { said:, filed:, lid: @lid,
                                 count: said.length })
            end

            private

            # {id of an entry => the id of the one that replaced it}.
            def replaced
                @replaced ||= @reading.inbox.each_with_object({}) do |e, out|
                    Array(e["replaces"]).each { out[it] = e["id"] }
                end
            end

            def row(entry)
                id = entry["id"]
                cls = if entry["taken"] then "is-done"
                      elsif replaced.key?(id) then ""
                      else "is-flight"
                      end
                @scope.partial(
                    "ledger/message",
                    { cls:, id:, state: state(entry), about: about(entry),
                      at: entry["at"] || "", body: body(entry) }
                )
            end

            def state(entry)
                id = entry["id"]
                if entry["taken"]
                    at = Clock.clock(entry["taken_at"])
                    at.empty? ? "filed" : "filed at #{at}"
                elsif replaced.key?(id)
                    "replaced by #{replaced[id]}"
                else
                    "awaiting filing"
                end
            end

            # What the entry is, in words.
            def about(entry)
                ref = entry["ref"]
                if Helpers.filled?(entry["word"]) && !entry["malformed"]
                    return "#{format(KINDS["word"], ref:)}: #{entry["word"]}"
                end

                kind = entry["malformed"] ? nil : Terms.kind(ref)
                kind = "ask" if kind == "answer" && entry["comment"]
                kind ? format(KINDS[kind], ref:) : "malformed line"
            end

            def body(entry)
                [strong("word: ", entry["word"]),
                 strong("chose: ", entry["choice"]), order(entry["order"]),
                 picks(entry["picks"]), notes(entry["notes"]),
                 text(entry["text"])].join
            end

            def said(inner) = %(<div class="said">#{inner}</div>)

            def strong(lead, value)
                return "" unless Helpers.filled?(value)

                said("#{lead}<strong>#{Text.escape(value)}</strong>")
            end

            def order(list)
                return "" unless Helpers.filled?(list)

                said("order: #{Text.escape(list.join(", "))}")
            end

            def picks(picks)
                (picks || {}).map do |item, pick|
                    said("#{Text.escape(item)}: " \
                         "<strong>#{Text.escape(pick)}</strong>")
                end.join
            end

            def notes(notes)
                (notes || {}).map do |option, note|
                    said("on #{Text.escape(option)}: #{@scope.inline(note)}")
                end.join
            end

            def text(text)
                return "" unless Helpers.filled?(text)

                %(<div class="said md">#{@blocks.html(text)}</div>)
            end
        end
    end
end
