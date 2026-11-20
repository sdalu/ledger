# frozen_string_literal: true

require_relative "blocks"
require_relative "cards"
require_relative "case"
require_relative "goals"
require_relative "flight"
require_relative "head"
require_relative "inbox"
require_relative "kit"
require_relative "mockups"
require_relative "nav"
require_relative "next_waiting"
require_relative "record"
require_relative "reading"
require_relative "refs"
require_relative "say_form"
require_relative "waiting"
require_relative "word_cards"
require_relative "word_form"

module LedgerViewer
    module Render
        # A ledger's page: render_ledger() of ledger-serve.py. Its top
        # half (the head with its tiles, Waiting on you, the list beside
        # the page, the goal, the note, Sent and Being prepared) ends
        # where the section of unfinished pieces opens; what follows is
        # the rest, which closes the page.
        class LedgerPage
            CRUMBS = '<p class="crumbs"><a href="/">All ledgers</a></p>'
            NOTE = "A note to the session working on this ledger"
            CUT = "\0cut\0"
            REST = "</div></div>"

            def initialize(scope, page)
                @scope = scope
                @page = page
            end

            # The page of the ledger `entry`, read as `data`.
            def html(entry, data, stamp, token)
                wrap(entry, body(entry, Reading.new(data), token).join, stamp)
            end

            # The page from its start to where the section of unfinished
            # pieces opens.
            def top(entry, data, stamp, token)
                top, = body(entry, Reading.new(data), token)
                wrap(entry, top + CUT, stamp).split(CUT, 2).first
            end

            private

            def wrap(entry, body, stamp)
                name = Helpers.project_name(entry.project, entry.path)
                @page.html(title: "Ledger #{name}", body:, stamp:, skip: true,
                           ledger: true)
            end

            # [the top half of the body, the rest of it].
            def body(entry, reading, token)
                kit = kit(entry, reading, token)
                top = CRUMBS + Head.new(kit, entry).html + layout(kit, token)
                [top, rest(kit)]
            end

            # What follows Being prepared: the unfinished pieces and the
            # criteria and checks (none when nothing remains), the
            # messages, and the record.
            def rest(kit)
                remains = kit.reading.settled? ? "" : Flight.new(kit).html
                remains + Inbox.new(kit).html + Record.new(kit).html + REST
            end

            def layout(kit, token)
                waiting, below = sections(kit, token)
                goals = Goals.new(kit.scope, kit.blocks, kit.lid)
                kit.scope.partial(
                    "ledger/layout",
                    { lid: kit.lid, waiting:, below:, nav: Nav.new(kit).html,
                      note: note(kit), goals: goals.html(kit.reading.goals) }
                )
            end

            def sections(kit, token)
                next_waiting = NextWaiting.new(kit.scope, kit.reading)
                cards = Cards.new(kit, next_waiting)
                words = WordCards.new(kit, next_waiting)
                Waiting.new(kit, cards, words, token).sections
            end

            def note(kit)
                kit.say.html(SayForm::BLANK.with(label: NOTE))
            end

            def kit(entry, reading, token)
                scope = @scope.page(titles(reading))
                cases = Case.new(scope)
                lid = entry.id
                Kit.new(scope:, reading:, lid:, cases:,
                        say: SayForm.new(scope, lid, token, cases),
                        word: WordForm.new(scope, lid, token),
                        refs: Refs.new(scope), blocks: Blocks.new(scope),
                        mockups: Mockups.new(scope, lid, entry.mockups,
                                             reading.statuses))
            end

            # What an id stands for, so that a link to it can say.
            def titles(reading)
                named = reading.questions.select { it["id"] }
                [[reading.pieces, "what"], [named, "text"],
                 [reading.criteria, "text"]].each_with_object({}) do |(l, k), h|
                    l.each { h[it["id"]] = title(it, k) }
                end
            end

            def title(item, key)
                text = item[key]
                text = Text.question_text(text) if item.key?("choices")
                Text.title_of(text).first
            end
        end
    end
end
