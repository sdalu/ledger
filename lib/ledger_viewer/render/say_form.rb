# frozen_string_literal: true

require_relative "say_ends"
require_relative "terms"
require_relative "text"

module LedgerViewer
    module Render
        # A form whose content goes to the ledger's inbox: an answer to
        # an O<n> (with its choices, a comment per option or per item), a
        # comment on a planned piece, a proposed order of the planned
        # pieces, or a note.
        class SayForm
            # ref, label; choices and items of a question; order of the
            # planned pieces; rec its recommendation, {label => why};
            # replaces the ids of the answer it replaces; prev that
            # answer, which the form opens holding; next_id the question
            # after this one; inside {item => its pictures}.
            include SayEnds

            Spec = Data.define(:ref, :label, :choices, :items, :order, :rec,
                               :replaces, :prev, :next_id, :inside)
            BLANK = Spec.new(ref: nil, label: "", choices: [], items: [],
                             order: [], rec: {}, replaces: [], prev: nil,
                             next_id: nil, inside: {})

            def initialize(scope, lid, token, cases)
                @scope = scope
                @lid = lid
                @token = token
                @cases = cases
            end

            def html(spec)
                @spec = spec
                @prev = spec.prev || {}
                @fid = "say-#{spec.ref || "note"}"
                @scope.partial(
                    "ledger/say",
                    { lid: @lid, token: @token, ref: spec.ref.to_s,
                      replaces: spec.replaces.join(", "), middle:, box:,
                      submit:, after: }
                )
            end

            private

            def choices? = !@spec.choices.empty?

            def folded? = choices? || !@spec.order.empty?

            def middle
                spec = @spec
                if choices? && !spec.items.empty? then per_item
                elsif choices? then per_choice
                elsif !spec.order.empty? then order
                else @scope.partial("ledger/say_label", fid: @fid,
                                                        label: spec.label)
                end
            end

            def fieldset(rows)
                @scope.partial("ledger/say_fieldset", label: @spec.label, rows:)
            end

            # The comment box of an option or an item; `needed` is the
            # id of the line saying what to write, when the key asks for
            # a comment.
            def note(key, what, needed = "")
                body = (@prev["notes"] || {}).fetch(key, "")
                asks = !needed.empty? && key.include?("in your comment")
                for_what = key.include?(" = ") ? key.partition(" = ").last : key
                @scope.partial(
                    "ledger/say_note", { key:, what:, body:, needed:, asks:,
                                         for_what: }
                )
            end

            def per_item
                picks = @prev["picks"] || {}
                rows = @spec.items.each_with_index.map do |item, at|
                    @scope.partial("ledger/say_pick", pick(item, at, picks))
                end
                fieldset(rows)
            end

            def pick(item, at, picks)
                { fid: @fid, at:, item:, picked: picks[item],
                  options: @spec.choices,
                  codes: @spec.choices.map { Terms.option_code(it) },
                  inside: @spec.inside.fetch(item, ""),
                  note: note(item, item) }
            end

            def per_choice
                rows = @spec.choices.each_with_index.map do |option, at|
                    @scope.partial("ledger/say_choice", choice(option, at))
                end
                fieldset(rows)
            end

            def choice(option, at)
                id = "#{@fid}-c#{at}"
                code = Terms.option_code(option)
                { id:, option:, checked: @prev["choice"] == option,
                  shown: @cases.option(option, @spec.rec, why: true),
                  note: note(option, code, "#{id}-needed") }
            end

            def order
                @scope.partial(
                    "ledger/say_order",
                    { fid: @fid, label: @spec.label,
                      order: @spec.order.join(", ") }
                )
            end
        end
    end
end
