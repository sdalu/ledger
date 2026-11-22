# frozen_string_literal: true

require_relative "text"

module LedgerViewer
    module Render
        # A row of a list on the ledger page, or with `card` a card whose
        # text is its heading. `kase` is the
        # facets under a card's head, `fold` ready-made markup after its
        # meta, `state` a status tag of its own before the id tag,
        # `tag_tip` what the status (else the tag) means, said on hover, and
        # `why` the icon to the links page, after the id tag, and `by`
        # the chip of an obsolete piece's successor, before it.
        class Entry
            Spec = Data.define(
                :cls, :tag, :text, :meta, :evidence, :done, :card, :anchor,
                :extra, :tag_tip, :detail, :state, :kase, :fold, :why, :by
            )
            BLANK = Spec.new(
                cls: "", tag: "", text: "", meta: "", evidence: "", done: "",
                card: false, anchor: "", extra: "", tag_tip: "", detail: "",
                state: "", kase: "", fold: "", why: "", by: ""
            )

            def initialize(scope) = @scope = scope

            def html(**fields)
                spec = BLANK.with(**fields)
                @scope.partial(
                    "ledger/entry",
                    { cls: spec.cls, card: spec.card, text: spec.text,
                      anchor: anchor(spec), tags: heads(spec),
                      extra: spec.extra, kase: spec.kase,
                      detail: detail(spec), rest: rest(spec) }
                )
            end

            # A card's contents under its head: the facets, the detail and
            # what follows it, for a card drawn in another frame (a row
            # that opens into its card).
            def body(**fields)
                spec = BLANK.with(**fields)
                "#{spec.kase}#{detail(spec)}#{rest(spec)}"
            end

            private

            def anchor(spec)
                spec.anchor.empty? ? "" : %( id="#{spec.anchor}")
            end

            # The tags, the successor's chip `by` beside them, the why icon.
            def heads(spec)
                by = spec.by.empty? ? "" : succ(spec.by)
                "#{tags(spec)}#{by}#{spec.why}"
            end

            def succ(chip)
                ' <span class="succ"><span aria-hidden="true">→</span> ' \
                    "<span class=\"visually-hidden\">obsoleted by</span> " \
                    "#{chip}</span>"
            end

            # The id tag, with the status's tag before it.
            def tags(spec)
                id = spec.tag.empty? ? "" : @scope.chip(spec.tag)
                return "#{folded(spec)} #{id}" if spec.card && status?(spec)
                return stated(spec, id) unless spec.state.empty?
                return id if spec.tag.empty? || spec.tag_tip.empty?

                tipped(spec)
            end

            def tipped(spec)
                attrs, box = @scope.tip(spec.tag_tip)
                @scope.chip(spec.tag, attrs) + box
            end

            def status?(spec) = !spec.state.empty? && !spec.tag_tip.empty?

            # A card's status is a fold inside its own pill: the meaning
            # opens after the word, which it does not repeat.
            def folded(spec)
                tip = spec.tag_tip
                says = tip.include?(": ") ? tip.partition(": ").last : tip
                "<details class=\"tag status status-fold\"><summary>" \
                    "#{Text.escape(spec.state)}</summary>" \
                    "<span class=\"status-says\">#{Text.escape(says)}</span>" \
                    "</details>"
            end

            def stated(spec, id)
                tip = spec.tag_tip
                attrs, box = tip.empty? ? ["", ""] : @scope.tip(tip)
                "<span class=\"tag status\"#{attrs}>" \
                    "#{Text.escape(spec.state)}</span>#{box} #{id}"
            end

            def detail(spec)
                return "" if spec.detail.empty?

                para = %(<p class="detail">#{@scope.inline(spec.detail)}</p>)
                return para if spec.kase.empty?

                "<details class=\"covers\"><summary>What it covers</summary>" \
                    "#{para}</details>"
            end

            # The meta, the fold, then what is done when and the evidence.
            def rest(spec)
                [div("meta", "", spec.meta), spec.fold,
                 div("evidence", "done when: ", spec.done),
                 div("evidence", "evidence: ", spec.evidence)].join
            end

            def div(cls, lead, text)
                return "" if text.empty?

                %(<div class="#{cls}">#{lead}#{@scope.inline(text)}</div>)
            end
        end
    end
end
