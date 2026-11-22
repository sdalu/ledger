# frozen_string_literal: true

require "ledger/text/awaits"
require "ledger/text/title"

module Ledger
    module Checks
        # The rules on the pieces: self-routed, pieces-order, verified-by
        # (U11), and their part of titles, details and case-rated.
        module Pieces
            # Their `check --fix-hints` lines, merged into HINTS.
            HINTS = {
                "self-routed" =>
                    "a piece is not routed to this ledger's own session; " \
                    '`bin/ledger piece PATH P<n> --status "kept: REASON"` or ' \
                    '`--route "sonnet, effort: medium"`',
                "pieces-order" =>
                    "a piece leaves planned only once what it waits for is " \
                    "verified or kept, and waits for none dropped; " \
                    "`bin/ledger piece PATH P<n> --status planned` or " \
                    "`--after …`",
                "verified-by" =>
                    "a piece is verified by someone other than its own " \
                    "route; " \
                    "`bin/ledger piece PATH P<n> --status verified " \
                    "--verified-by me`"
            }.freeze

            SELF = "%s is routed to this ledger's own session (%s): keep " \
                   "it (kept: reason) or route it to a delegate"
            AWAITING = "a piece awaiting the user's word without a "
            # Where a piece leaves planned, its after pieces are settled.
            LEFT = %w[out back verified].freeze

            module_function

            # A piece in flight routed `peer:` to the ledger's own project,
            # with no word of the user awaited.
            def self_routed(derive)
                own = derive.project.downcase
                derive.pieces.filter_map do |piece|
                    next unless piece[:peer]&.downcase == own &&
                                derive.in_flight?(piece) &&
                                derive.awaits(piece).empty?
                    format(SELF, derive.ref(piece), derive.project)
                end
            end

            # A piece waiting for a dropped one; a piece out, back or
            # verified before what it waits for is settled.
            def order(derive)
                derive.pieces.flat_map do |piece|
                    after = derive.after(piece)
                    [dropped(derive, piece, after),
                     early(derive, piece, after)].compact
                end
            end

            def dropped(derive, piece, after)
                gone = after.select { it[:status] == "dropped" }
                return if gone.empty? || piece[:status] == "dropped"
                "#{derive.ref(piece)} waits for dropped #{refs(derive, gone)}"
            end

            def early(derive, piece, after)
                waiting = after.reject { derive.settled?(it) }
                return if waiting.empty? || !LEFT.include?(piece[:status])
                "#{derive.ref(piece)} [#{piece[:status]}] before " \
                    "#{refs(derive, waiting)} is verified"
            end

            def titles(derive)
                in_flight(derive) { Text::Title.problem(it[:title]) }
            end

            def details(derive)
                in_flight(derive) do |piece|
                    Text::Title.detail_problem(piece[:detail].to_s)
                end
            end

            # A piece awaiting the user's word without a problem or a
            # rated risk.
            def rated(derive)
                derive.pieces.flat_map do |piece|
                    next [] if derive.awaits(piece).empty?
                    head = "#{derive.ref(piece)}: #{AWAITING}"
                    problem = "`— problem:`" \
                        unless derive.present?(piece[:problem])
                    risk = "rated `— risk: N/10 — …`" unless piece[:risk_rating]
                    [problem, risk].compact.map { "#{head}#{it}" }
                end
            end

            # A verified piece whose verified_by is its own route.
            def verified_by(derive)
                derive.pieces.filter_map do |piece|
                    who = piece[:verified_by]
                    next unless piece[:status] == "verified" &&
                                routes(piece).include?(who)
                    "#{derive.ref(piece)} is verified by its own route (#{who})"
                end
            end

            # The piece's route as `--route` spells it, with and without
            # its skills.
            def routes(piece)
                return ["peer: #{piece[:peer]}"] if piece[:peer]
                base = "#{piece[:model]}, effort: #{piece[:effort]}"
                return [base] unless piece[:skills]
                [base, "#{base}, skills: #{piece[:skills]}"]
            end

            def in_flight(derive)
                derive.pieces.filter_map do |piece|
                    next unless derive.in_flight?(piece)
                    why = yield(piece)
                    "#{derive.ref(piece)}: #{why}" if why
                end
            end

            def refs(derive, pieces) = pieces.map { derive.ref(it) }.join(", ")
        end

        # pieces-awaits: the states a word may be awaited in, and a scope
        # only for a word awaited; the words themselves are the schema's.
        module Awaits
            # Their `check --fix-hints` lines, merged into HINTS.
            HINTS = {
                "pieces-awaits" =>
                    "start only on a planned or kept piece, commit, deploy, " \
                    "push and merge on a piece done; `bin/ledger piece PATH " \
                    'P<n> --awaits "commit, deploy"`; a scope names only ' \
                    "words the piece awaits: " \
                    '`--scope "commit = … | deploy = …"`'
            }.freeze

            START = "%s [%s] awaits start, which begins a planned or kept " \
                    "piece"
            FINISH = "%s [%s] awaits %s, which only finish a piece that " \
                     "is done"

            module_function

            # start on a piece neither planned nor kept, a finishing word
            # on one not settled, a scope for a word not awaited.
            def problems(derive)
                derive.pieces.flat_map do |piece|
                    words = derive.awaits(piece).map(&:first)
                    [start(derive, piece, words),
                     finish(derive, piece, words)].compact
                end + scopes(derive)
            end

            def start(derive, piece, words)
                return unless words.include?("start") &&
                              !%w[planned kept].include?(piece[:status])
                format(START, derive.ref(piece), piece[:status])
            end

            def finish(derive, piece, words)
                late = words.select { Text::Awaits.finish?(it) }
                return if late.empty? || derive.settled?(piece)
                format(FINISH, derive.ref(piece), piece[:status],
                       late.join(", "))
            end

            def scopes(derive)
                derive.pieces.filter_map do |piece|
                    words = derive.awaits(piece).map(&:first)
                    stray = derive.scopes(piece).map { it[:word] } - words
                    next if stray.empty?
                    "#{derive.ref(piece)} scope names #{stray.join(", ")}, " \
                        "which it does not await"
                end
            end
        end
    end
end
