# frozen_string_literal: true

require "ledger/text/awaits"
require "ledger/text/risk"
require "ledger/text/title"

module Ledger
    module Commands
        # `piece PATH new|P<n> [--status --route --title --what --done-when
        # --evidence --after --for --problem --risk --plan --scope --awaits
        # --verified-by --session --by]`: add a piece or change one; `--by
        # X<n>` writes the decision's led_to edge to it, `--status out`
        # claims it for the session (U12).
        class Piece < CLI::Command
            USAGE = "PATH TARGET"
            SYNOPSIS = "PATH new|P<n> [--FIELD VALUE...]"
            SUMMARY = "add a piece or change one: status, route, links, the " \
                      "word it awaits"
            ID = /\AP[1-9]\d*\z/
            # Each flag and what its value is, as the help says it.
            FLAGS = {
                "status" => "planned, out, back, verified, blocked, dropped " \
                            "or kept: REASON",
                "route" => "who does it: MODEL, effort: E[, skills: S], " \
                           "or peer: SESSION",
                "title" => "a short name, at most 60 characters",
                "what" => "the detail: what it covers",
                "done-when" => "how its finish is checked",
                "evidence" => "what showed it verified",
                "after" => "P<n>,... it waits for",
                "for" => "D<n>,... the criteria it serves",
                "problem" => "what is wrong or missing, for an awaited word",
                "risk" => "N/10 — what is at stake",
                "plan" => "what will be done on the word",
                "scope" => "commit = what it authorises | deploy = ...",
                "awaits" => "start, commit, deploy, push, merge or " \
                            "other (what)",
                "verified-by" => "who checked it: me, a route, peer: SESSION",
                "session" => "who claims an out ($CLAUDE_CODE_SESSION_ID)",
                "by" => "X<n>, the decision that led to it"
            }.freeze

            private

            def flags(parser)
                FLAGS.each do |name, what|
                    parser.on("--#{name} VALUE", what) { @opts[name] = it }
                end
                dry_run(parser)
            end

            def run(path, target)
                refuse("the target is `new` or P<n>") unless
                    target == "new" || ID.match?(target)
                result = save(path, target, session)
                lines = [Render::Markdown.line(result.after, result.value)]
                emit(result, path, first: (result.value if target == "new"),
                                   lines:)
                0
            end

            def save(path, target, holder)
                write(path, own: (target unless target == "new")) do |change|
                    PieceWriter.new(change, journal.db, @opts, holder)
                               .call(target, Address.parse(path))
                end
            end

            # U12: the session an `out` is claimed for; Change#status
            # refuses an `out` without one.
            def session
                id = @opts["session"] || ENV.fetch("CLAUDE_CODE_SESSION_ID",
                                                   nil)
                id unless id.to_s.strip.empty?
            end
        end

        # The rows one `piece` command changes: the piece, its links, its
        # awaited words and their scope, the led_to edge of `--by`, and the
        # claim of `--status out`.
        class PieceWriter
            BY = /\AX[1-9]\d*\z/
            # The flag of each piece_links kind and the column it fills.
            LINKS = { "after" => %w[P after_id],
                      "for" => %w[D criterion_id] }.freeze

            def initialize(change, db, opts, session)
                @change = change
                @db = db
                @opts = opts
                @session = session
            end

            # -> the piece's visible id, once every row is written.
            def call(target, address)
                old = target == "new" ? nil : find(target, address)
                row = PieceRow.new(old, @opts, awaits: listed(old, :awaits),
                                               scopes: listed(old, :scopes))
                id = save(old, row)
                links(id)
                PieceWords.new(@change, @db, id).sync(row.awaits, row.scopes)
                by(id)
                claim(id, row)
                @change.own
            end

            private

            def find(target, address)
                @change.resolve(target).last
            rescue Unknown
                raise Refused, "no #{target} under Pieces in #{address}"
            end

            def save(old, row)
                columns = row.columns
                return update(old, columns) if old

                n = @change.next_id("P")
                @change.own = "P#{n}"
                @change.insert(:pieces, n:, **columns)
            end

            def update(old, columns)
                @change.update(:pieces, old[:id], **columns)
                old[:id]
            end

            # [[word, what]] of the piece's awaits or [[word, text]] of its
            # scope, as stored; [] for a new piece.
            def listed(old, kind)
                return [] unless old

                table, column = { awaits: %i[piece_awaits what],
                                  scopes: %i[piece_scopes text] }.fetch(kind)
                rows(table, old[:id]).map { [it[:word], it[column].to_s] }
            end

            def rows(table, id) = PieceWords.rows(@db, table, id)

            def links(id)
                LINKS.each do |flag, (letter, column)|
                    next unless @opts.key?(flag)

                    @db[:piece_links].where(piece_id: id, kind: flag)
                                     .select_map(:id)
                                     .each { @change.delete(:piece_links, it) }
                    ids(flag, letter).each_with_index do |ref, position|
                        insert_link(id, flag, position, column => row_of(ref))
                    end
                end
            end

            def insert_link(id, kind, position, target)
                @change.insert(:piece_links, piece_id: id, kind:, position:,
                                             **target)
            end

            def ids(flag, letter)
                @opts[flag].split(/[,\s]+/).reject(&:empty?).each do |ref|
                    next if ref.start_with?(letter)

                    raise Refused, "--#{flag} takes #{letter} ids, not #{ref}"
                end
            end

            def row_of(ref) = @change.resolve(ref).last[:id]

            # `--by X<n>`: the decision that led to the piece.
            def by(id)
                ref = @opts["by"]&.strip or return
                raise Refused, "--by takes a decision id, X<n>" unless
                    BY.match?(ref)

                piece = "P#{@db[:pieces].where(id:).get(:n)}"
                @change.link("led_to", ref, piece) unless led?(ref, id)
            end

            def led?(ref, id)
                @db[:links].where(ledger_id: @change.ledger_id, kind: "led_to",
                                  from_row: row_of(ref), to_kind: "P",
                                  to_row: id).any?
            end

            def claim(id, row)
                @change.status(id, "out", session: @session) if row.claim?
            end
        end

        # The awaited words of one piece and their scope lines, written as
        # the lists a `piece` command asks for.
        class PieceWords
            def self.rows(db, table, id)
                db[table].where(piece_id: id).order(:position, :id).all
            end

            def initialize(change, db, id)
                @change = change
                @db = db
                @id = id
            end

            def sync(awaits, scopes)
                sync_awaits(@id, awaits)
                sync_scopes(@id, scopes)
            end

            private

            def rows(table, id) = PieceWords.rows(@db, table, id)

            # The awaited words as WORDS lists them; a row whose word
            # stays keeps its insert event, so its wait keeps its age.
            def sync_awaits(id, words)
                old = rows(:piece_awaits, id)
                words.each_with_index do |(word, what), position|
                    what = nil if what.to_s.empty?
                    row = old.find { it[:word] == word && it[:what] == what }
                    next await(id, position, word, what) unless row

                    old.delete(row)
                    move(:piece_awaits, row, position)
                end
                old.each { @change.delete(:piece_awaits, it[:id]) }
            end

            def await(id, position, word, what)
                @change.insert(:piece_awaits, piece_id: id, position:, word:,
                                              what:)
            end

            def move(table, row, position)
                return if row[:position] == position

                @change.update(table, row[:id], position:)
            end

            def sync_scopes(id, pairs)
                old = rows(:piece_scopes, id)
                return if old.map { [it[:word], it[:text]] } == pairs

                old.each { @change.delete(:piece_scopes, it[:id]) }
                pairs.each_with_index do |(word, text), position|
                    @change.insert(:piece_scopes, piece_id: id, position:,
                                                  word:, text:)
                end
            end
        end

        # The flags of `piece` that set one column or a few, each applied
        # to @row from @opts; a value that is not the column's shape is
        # refused.
        module PieceFlags
            STATUSES = %w[planned out back verified blocked dropped].freeze
            SKILL = '[\p{Word}.:-]+'
            MODEL = Regexp.new(
                "\\A(haiku|sonnet|opus|fable), " \
                "effort: (low|medium|high|xhigh|max)" \
                "(?:, skills: (#{SKILL}(?:, #{SKILL})*))?\\z"
            )
            PEER = /\Apeer: ([\p{Word}.-]+)\z/
            NO_ROUTE = { model: nil, effort: nil, skills: nil,
                         peer: nil }.freeze
            PROSE = { "done-when" => :done_when, "evidence" => :evidence,
                      "problem" => :problem, "risk" => :risk,
                      "plan" => :plan, "verified-by" => :verified_by }.freeze
            ROUTE = "--route (`sonnet, effort: medium[, skills: c]` or " \
                    "`peer: SESSION`) or --status 'kept: REASON'"

            private

            def refuse(message) = raise(Refused, message)

            # The title and the detail, each set on its own.
            def what
                return unless @opts.key?("title") || @opts.key?("what")

                title = @opts.fetch("title", @row[:title]).to_s.strip
                detail = @opts.fetch("what", @row[:detail]).to_s.strip
                titled(title, detail)
                @row.merge!(title:, detail: (detail unless detail.empty?))
            end

            def titled(title, detail)
                why = Text::Title.problem(title) ||
                      Text::Title.detail_problem(detail)
                refuse(why) if why
            end

            def prose
                PROSE.each do |flag, column|
                    next unless @opts.key?(flag)

                    value = @opts[flag].strip
                    @row[column] = value.empty? ? nil : value
                end
                @row[:risk_rating] = @row[:risk] &&
                                     Text::Risk.rating(@row[:risk]).first
            end

            def route
                value = @opts["route"]&.strip or return
                @row.merge!(NO_ROUTE)
                if (match = MODEL.match(value))
                    @row.merge!(model: match[1], effort: match[2],
                                skills: match[3])
                elsif (match = PEER.match(value))
                    @row[:peer] = match[1]
                elsif !value.empty?
                    refuse(ROUTE)
                end
            end

            def status
                word = @opts["status"]&.strip or return
                if word.start_with?("kept:")
                    kept(word.delete_prefix("kept:").strip)
                elsif STATUSES.include?(word)
                    @row.merge!(status: word, kept_reason: nil)
                else
                    refuse("--status #{word}: one of " \
                           "#{STATUSES.join(", ")}, or 'kept: REASON'")
                end
            end

            def kept(reason)
                refuse("--status 'kept: REASON' says why") if reason.empty?
                @row.merge!(status: "kept", kept_reason: reason)
            end
        end

        # The pieces columns a `piece` command asks for: the old row, or a
        # new piece's defaults, with each flag given applied; refused when
        # the result breaks a rule a piece keeps. AWAITS and SCOPES are
        # the stored [[word, what]] and [[word, text]] lists.
        class PieceRow
            include PieceFlags

            COLUMNS = (%i[status kept_reason dash title detail risk_rating] +
                       NO_ROUTE.keys + PROSE.values).freeze
            NEW = COLUMNS.to_h { [it, nil] }
                         .merge(status: "planned", dash: true).freeze
            VERIFIED = "--status verified needs --verified-by WHO: me, " \
                       "the route that checked it, or peer: SESSION"

            attr_reader :awaits, :scopes

            def initialize(old, opts, awaits:, scopes:)
                @old = old
                @opts = opts
                @row = (old || NEW).slice(*COLUMNS)
                [method(:what), method(:prose), method(:route),
                 method(:status)].each(&:call)
                @awaits = awaits_of(awaits)
                @scopes = scopes_of(scopes)
                complete
            end

            # Whether the command claims the piece (`--status out`).
            def claim? = @opts["status"]&.strip == "out"

            # The columns to write: a claimed piece reaches `out` through
            # Change#status, which checks the holder; any other status set
            # clears the claim.
            def columns
                out = @row.dup
                if claim?
                    out.delete(:status)
                    out[:status] = "planned" if @old.nil? || kept?(@old)
                elsif @opts.key?("status")
                    out[:claimed_by] = nil
                end
                out
            end

            private

            def kept?(row) = row[:status] == "kept"

            def awaits_of(stored)
                return stored unless @opts.key?("awaits")

                value = @opts["awaits"].strip
                return [] if value.empty?

                Text::Awaits.parse(value) or
                    refuse("--awaits: #{value}: words of start, commit, " \
                           "deploy, push, merge or other (what)")
            end

            def scopes_of(stored)
                pairs = @opts.key?("scope") ? scope_words : stored
                stray = pairs.map(&:first) - @awaits.map(&:first)
                return pairs if stray.empty?

                awaited = Text::Awaits.label(@awaits)
                awaited = "nothing" if awaited.empty?
                refuse("--scope names #{stray.join(", ")}, which " \
                       "#{@old ? "P#{@old[:n]}" : "the piece"} does not " \
                       "await (awaits: #{awaited})")
            end

            def scope_words
                value = @opts["scope"].strip
                return [] if value.empty?

                Text::Awaits.scope_words(value) or
                    refuse("--scope is `WORD = what it authorises`, parts " \
                           "joined by ` | `")
            end

            # The rules on the whole row, in the order the refusals are tested.
            def complete
                refuse("--title is required for a new piece") unless
                    @row[:title]
                awaiting
                routed
                refuse(VERIFIED) if @opts["status"]&.strip == "verified" &&
                                    @row[:verified_by].nil?
            end

            # What waits on the user's word is read cold, on a card: it
            # says what is at stake, the risk rated.
            def awaiting
                return if @awaits.empty?

                why = Text::Risk.case_problem(@row[:problem].to_s,
                                              @row[:risk].to_s)
                refuse("a piece awaiting the user's word gives #{why}") if why
            end

            # A kept piece has no route; any other has one.
            def routed
                return @row.merge!(NO_ROUTE) if kept?(@row)

                refuse(ROUTE) unless @row[:model] || @row[:peer]
            end
        end
    end
end
