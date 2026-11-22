# frozen_string_literal: true

require_relative "clock"
require_relative "helpers"
require_relative "question_meta"
require_relative "reading"
require_relative "say_form"
require_relative "recommend"
require_relative "terms"
require_relative "text"

module LedgerViewer
    module Render
        # The cards of the questions: to answer, sent and awaiting
        # filing, being prepared.
        class Cards
            include QuestionMeta

            def initialize(kit, waiting)
                @scope = kit.scope
                @reading = kit.reading
                @kit = kit
                @waiting = waiting
            end

            # A question the user can answer, with what they asked about
            # it, or one they answered and the session has not filed.
            def ask(question)
                id = question["id"]
                asked, said = sent_on(id)
                shown, inside = pictures(question)
                form = @kit.say.html(spec(question, said, inside))
                kase = case_of(question) + shown
                if said.empty?
                    return waiting_card(question, kase,
                                        form + @kit.word.ask(id, asked))
                end

                received(question, said.last, kase, form)
            end

            # A question whose options a piece is still preparing.
            def preparing(question)
                head = head(question, "is-flight is-card",
                            @kit.word.drop(question["id"]),
                            unready(question))
                shown = @kit.mockups.layout(question["pictures"]).first
                "#{head}#{case_of(question)}#{shown}</li>"
            end

            private

            # What was sent on a question and not filed: the comments
            # about it, then the answers; a picture asked is neither.
            def sent_on(id)
                sent = @reading.unfiled_on(id)
                [sent.select { it["comment"] },
                 sent.reject { Terms.aside?(it) }]
            end

            def case_of(question)
                @kit.cases.block(question) + @kit.raid.question(question) +
                    @kit.refs.fold(question["see"], @reading.refs)
            end

            # The pictures; each item of a question with a choice per
            # item has its own.
            def pictures(question)
                items = question["choices"].empty? ? [] : question["items"]
                shown, inside = @kit.mockups.layout(question["pictures"], items)
                [before(question, shown), inside]
            end

            # The question's own pictures, said to be the Before when its
            # options draw their own (a question answered per item draws
            # none).
            def before(question, shown)
                named = question["pictures"].any? { it["name"] }
                afters = question["items"].empty? &&
                         question["choices"].any? { it["picture"] }
                return shown unless named && afters

                %(<p class="mock-label">Before</p>#{shown})
            end

            def spec(question, said, inside)
                after = said.empty? ? @reading.next_of[question["id"]] : nil
                SayForm::BLANK.with(
                    ref: question["id"], label: label(question),
                    choices: Reading.options(question),
                    items: question["items"],
                    rec: recommended(question), inside:,
                    replaces: said.map { it["id"] }, prev: said.last,
                    next_id: after, shots: @kit.mockups.shots(question)
                )
            end

            def recommended(question)
                Recommend.of(question["recommend"], Reading.options(question),
                             question["items"])
            end

            # The head of a card: its title, id, drop and meta; a question
            # has no links page, so no icon to one.
            def head(question, cls, extra = "", meta = "")
                @scope.partial(
                    "ledger/card",
                    { cls:, anchor: "q-#{question["id"]}",
                      text: question["title"], tag: question["id"], extra:,
                      why: "", kase: "", detail: question["detail"].to_s,
                      meta: }
                )
            end

            def waiting_card(question, kase, form)
                head = head(question, "is-ask is-card",
                            @kit.word.drop(question["id"]),
                            waiting_since(question))
                picture = @kit.picture.question(question)
                "#{head}#{kase}#{form}#{picture}</li>"
            end

            def received(question, last, kase, form)
                @scope.partial(
                    "ledger/received",
                    { head: head(question, "is-flight is-card"), kase:, form:,
                      parts: Helpers.answer_parts(last), said: said(last),
                      id: last["id"], receipt: Clock.receipt(last),
                      next_waiting: @waiting.html("q-#{question["id"]}"),
                      lid: @kit.lid,
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
