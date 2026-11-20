# frozen_string_literal: true

require_relative "clock"
require_relative "helpers"
require_relative "question_meta"
require_relative "say_form"
require_relative "recommend"
require_relative "text"

module LedgerViewer
    module Render
        # The cards of the questions: to answer, sent and awaiting
        # filing, being prepared. ask() and preparing() of
        # ledger-serve.py.
        class Cards
            include QuestionMeta

            def initialize(kit, waiting)
                @scope = kit.scope
                @reading = kit.reading
                @kit = kit
                @waiting = waiting
            end

            # A question the user can answer, or has answered and the
            # session has not filed.
            def ask(question)
                id = question["id"]
                return plain(question) unless id

                said = @reading.unfiled_on(id)
                shown, inside = pictures(question)
                form = @kit.say.html(spec(question, said, inside))
                kase = case_of(question) + shown
                return waiting_card(question, kase, form) if said.empty?

                received(question, said.last, kase, form)
            end

            # A question whose options a piece is still preparing.
            def preparing(question)
                head = head(question, "is-flight is-card",
                            @kit.word.drop(question["id"]),
                            unready(question))
                shown = @kit.mockups.layout(question["text"]).first
                "#{head}#{case_of(question)}#{shown}</li>"
            end

            private

            def plain(question)
                text = question["text"]
                @scope.partial("ledger/plain", cls: "is-fail", tag: "no id",
                                               text:)
            end

            def case_of(question)
                @kit.cases.block(question) +
                    @kit.refs.fold(question["text"], @reading.refs)
            end

            # The pictures; each item of a question with a choice per
            # item has its own.
            def pictures(question)
                items = question["choices"].empty? ? [] : question["items"]
                @kit.mockups.layout(question["text"], items)
            end

            def spec(question, said, inside)
                after = said.empty? ? @reading.next_of[question["id"]] : nil
                SayForm::BLANK.with(
                    ref: question["id"], label: label(question),
                    choices: question["choices"], items: question["items"],
                    rec: recommended(question), inside:,
                    replaces: said.map { it["id"] }, prev: said.last,
                    next_id: after
                )
            end

            def recommended(question)
                said = Text.case_of(question["text"])["recommend"]
                Recommend.of(said, question["choices"], question["items"])
            end

            # The head of a card: its title, id, drop and meta.
            def head(question, cls, extra = "", meta = "")
                text = Text.question_text(question["text"])
                title, detail = Text.title_of(text)
                @scope.partial(
                    "ledger/card",
                    { cls:, anchor: "q-#{question["id"]}", text: title,
                      tag: question["id"], extra:, kase: "", detail:, meta: }
                )
            end

            def waiting_card(question, kase, form)
                head = head(question, "is-ask is-card",
                            @kit.word.drop(question["id"]),
                            waiting_since(question))
                "#{head}#{kase}#{form}</li>"
            end

            def received(question, last, kase, form)
                @scope.partial(
                    "ledger/received",
                    { head: head(question, "is-flight is-card"), kase:, form:,
                      summary: Helpers.answer_summary(last), said: said(last),
                      id: last["id"], receipt: Clock.receipt(last),
                      next_waiting: @waiting.html, lid: @kit.lid,
                      ref: question["id"] }
                )
            end

            # What the user wrote under a choice, drawn as Markdown.
            def said(last)
                text = Text.strip(last["text"])
                chosen = Helpers.filled?(last["choice"]) ||
                         Helpers.filled?(last["picks"])
                return "" if text.empty? || !chosen

                @scope.partial("ledger/said", html: @kit.blocks.html(text))
            end
        end
    end
end
