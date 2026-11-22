# frozen_string_literal: true

require "ledger/hold"
require "ledger/text/waited"

module Ledger
    # What Derive says of a piece ready to send: ready, since when, and
    # unsent once it has stayed ready past the limit. Mixed into Derive,
    # which gives `pieces`, `after`, `awaits_rows`, `touched_at`, the
    # events (`@activity`), the clock (`@now`) and the limit
    # (`@ready_ms`).
    module Ready
        # What an after: piece may be for its follower to be sent.
        ENDED = %w[verified kept dropped obsolete].freeze
        # How long a ready piece may stay planned, in minutes, before it
        # is unsent (S2); LEDGER_READY_LIMIT overrides.
        LIMIT = 120
        LIMIT_ENV = "LEDGER_READY_LIMIT"

        # The limit, read once: a value that is not a whole number above
        # 0 is refused, naming the variable, rather than replaced by the
        # default.
        def self.limit
            @limit ||= parse(ENV.fetch(LIMIT_ENV, nil))
        end

        def self.parse(value) = Derive.minutes(LIMIT_ENV, value, LIMIT)

        # A planned piece awaiting no word whose `after` pieces are all
        # verified, kept, dropped or obsolete, and that is not held.
        def ready?(piece)
            piece[:status] == "planned" && awaits_rows(piece).empty? &&
                after(piece).all? { ENDED.include?(it[:status]) } &&
                held(piece).nil?
        end

        # Why the piece is held back on purpose (`piece --hold`), nil when
        # it is not, or the piece it names has settled.
        def held(piece) = Hold.active(piece, pieces)

        # The pieces held back, in row order.
        def held_pieces = pieces.select { held(it) }

        # [[piece, age in ms]] of the pieces unsent, in row order: ready
        # for longer than the limit.
        def unsent
            pieces.select { unsent?(it) }
                  .map { [it, @now - ready_since(it)] }
        end

        def unsent?(piece)
            since = ready_since(piece)
            !since.nil? && @now - since > @ready_ms
        end

        # When a ready piece became ready (ms): the later of its own last
        # change and its `after` pieces' last ending; nil when it is not
        # ready, or when no event dates it.
        def ready_since(piece)
            return unless ready?(piece)
            raise ArgumentError, "the times need the events" unless @activity

            [touched_at(piece),
             *after(piece).map { @activity.ended_at(it) }].compact.max
        end

        # `P65 (2 days)`: an unsent piece with its age.
        def unsent_label(piece, age) = "#{ref(piece)} (#{Text.span(age)})"
    end
end
