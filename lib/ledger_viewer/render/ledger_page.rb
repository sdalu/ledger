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
require_relative "picture_fold"
require_relative "next_waiting"
require_relative "raid"
require_relative "ties"
require_relative "record"
require_relative "reading"
require_relative "refs"
require_relative "say_form"
require_relative "unmet"
require_relative "waiting"
require_relative "waker"
require_relative "word_cards"
require_relative "word_form"

module LedgerViewer
    module Render
        # A ledger's page. Its top half (the head with its tiles,
        # Waiting on you, the list beside the page, the goal, the note,
        # Sent and Being prepared) ends where the section of unfinished
        # pieces opens; what follows is the rest, which closes the page.
        class LedgerPage
            CRUMBS = '<p class="crumbs"><a href="/">All ledgers</a></p>'
            NOTE = "A note to the session working on this ledger"
            REST = "</div></div>"

            # ledgers: where a picture's bytes are read; config: whose
            # session secret signs the keys to a ledger's pictures.
            def initialize(scope, page, ledgers, config)
                @scope = scope
                @page = page
                @ledgers = ledgers
                @secret = config.session_secret
            end

            # The page of the ledger `entry`, its document `data`.
            def html(entry, data, stamp, token)
                wrap(entry, body(entry, Reading.new(data), token).join, stamp)
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
                waking = @ledgers.waker(entry)
                switch = Waker.new(kit.scope, kit.lid, token)
                head = Head.new(kit, entry, switch.html(waking),
                                on: waking.on,
                                unread: switch.unread(waking,
                                                      kit.reading.unread))
                top = CRUMBS + head.html + layout(kit, token)
                [top, rest(kit)]
            end

            # What follows Being prepared: the unfinished pieces and the
            # checks (none when nothing remains), the messages, and the
            # record.
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
                      note: note(kit), goals: goals.html(kit.reading.goals),
                      criteria: criteria(kit) }
                )
            end

            # The criteria not met, under the Goal; none once nothing
            # remains, when the page says what closes the ledger instead.
            def criteria(kit)
                kit.reading.settled? ? "" : Unmet.new(kit).html
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
                        raid: Raid.new(scope, reading),
                        ties: Ties.new(scope, reading),
                        **forms(scope, lid, token, reading, cases),
                        refs: Refs.new(scope), blocks: Blocks.new(scope),
                        mockups: Mockups.new(scope, files_path(lid), reading,
                                             bytes(entry)))
            end

            # Where the page's pictures are fetched from: under a key good
            # for this ledger and an hour, which a frame without a session
            # needs. A page swapped in later carries a fresh one.
            def files_path(lid)
                "/m/k/#{MockupToken.issue(@secret, lid)}/#{lid}"
            end

            # The builders of the page's forms: answers, words, pictures.
            def forms(scope, lid, token, reading, cases)
                { say: SayForm.new(scope, lid, token, cases),
                  word: WordForm.new(scope, lid, token),
                  picture: PictureFold.new(scope, lid, token, reading) }
            end

            # The bytes of a picture of one file, by its name.
            def bytes(entry)
                lambda do |name|
                    @ledgers.picture(entry, name, "").fetch(:bytes).to_s
                end
            end

            # What an id stands for, so that a link to it can say.
            def titles(reading)
                titled = (reading.pieces + reading.questions)
                         .to_h { [it["id"], it["title"]] }
                reading.criteria.each do |criterion|
                    title, = Text.title_of(criterion["text"])
                    titled[criterion["id"]] = title
                end
                titled.merge(assumed(reading))
            end

            # An assumption stands for its text.
            def assumed(reading)
                reading.assumptions.to_h { [it["id"], it["text"]] }
            end
        end
    end
end
