# frozen_string_literal: true

require "json"

require "ledger/snapshot"
require "ledger/text/awaits"

module Ledger
    # The derived states (docs/journal.md, section 3): computed per read
    # from a Snapshot, and from the events where a state is about time
    # (stalled, asked since), never stored.
    #
    #     derive = Ledger::Derive.read(db, snapshot)
    #     derive.ready?(piece); derive.stalled?(piece)
    #     Ledger::Derive::StatusLine.new(derive).to_s
    #
    # Requiring this file loads the check rules too: the status line
    # proposes closing only when `--final` passes.
    class Derive
        # The stall budget in minutes (S2); LEDGER_STALL_MINUTES overrides.
        STALL_MINUTES = 60
        SETTLED    = %w[verified kept].freeze
        UNFINISHED = %w[planned out back].freeze
        # What is in flight, most urgent first.
        IN_FLIGHT  = %w[blocked back out planned].freeze
        STALL_ENV  = "LEDGER_STALL_MINUTES"

        # The budget, read once: a value that is not a whole number above
        # 0 is refused rather than replaced by the default.
        def self.stall_minutes
            @stall_minutes ||= parse_stall(ENV.fetch(STALL_ENV, nil))
        end

        def self.parse_stall(value)
            return STALL_MINUTES if value.nil?
            minutes = value.to_i
            return minutes if /\A[0-9]+\z/.match?(value) && minutes.positive?
            raise Refused, "#{STALL_ENV}=#{value}: a whole number of " \
                           "minutes above 0"
        end

        # A Derive with the ledger's activity read from the events.
        def self.read(db, snapshot, now: Write.now,
                      stall_minutes: self.stall_minutes)
            new(snapshot, activity: Activity.read(db, snapshot), now:,
                          stall_minutes:)
        end

        attr_reader :snapshot

        # ACTIVITY is needed by the states about time alone; a Derive made
        # without it answers every other state and refuses those.
        def initialize(snapshot, activity: nil, now: nil,
                       stall_minutes: STALL_MINUTES)
            @snapshot = snapshot
            @activity = activity
            @now = now
            @stall_ms = stall_minutes * 60_000
            @pieces = snapshot.pieces.to_h { [it[:id], it] }
            @criteria = snapshot.criteria.to_h { [it[:id], it] }
        end

        def project = snapshot.ledger[:project]
        def pieces = snapshot.pieces
        def criteria = snapshot.criteria
        def piece(id) = @pieces.fetch(id)
        def criterion(id) = @criteria.fetch(id)
        def ref(piece) = "P#{piece[:n]}"

        def settled?(piece) = SETTLED.include?(piece[:status])
        def unfinished?(piece) = UNFINISHED.include?(piece[:status])
        def in_flight?(piece) = IN_FLIGHT.include?(piece[:status])

        # The pieces in flight, most urgent first, in row order within one
        # status.
        def in_flight
            pieces.select { in_flight?(it) }
                  .sort_by { [IN_FLIGHT.index(it[:status]), it[:id]] }
        end

        # A planned piece whose `after` pieces are all settled.
        def ready?(piece)
            piece[:status] == "planned" && after(piece).all? { settled?(it) }
        end

        # An out piece no event has touched for more than the budget.
        def stalled?(piece)
            raise ArgumentError, "stalled? needs the events" unless @activity
            return false unless piece[:status] == "out"
            @now - @activity.touched.fetch(piece[:id]) > @stall_ms
        end

        def after(piece) = links(piece, "after").map { piece(it[:after_id]) }

        def serves(piece)
            links(piece, "for").map { criterion(it[:criterion_id]) }
        end

        # [[word, what]] in position order, `what` "" but for other.
        def awaits(piece)
            awaits_rows(piece).map { [it[:word], it[:what].to_s] }
        end

        def awaits_rows(piece) = rows(:piece_awaits, :piece_id, piece)

        def awaits_label(piece) = Text::Awaits.label(awaits(piece))
        def scopes(piece) = rows(:piece_scopes, :piece_id, piece)

        def open_questions = snapshot.questions.select { it[:closed_at].nil? }
        def qref(question) = "O#{question[:n]}"

        # The piece that still prepares QUESTION: its `by` piece, then the
        # pieces its pending pictures name, the first not settled; nil
        # when the question is answerable.
        def preparer(question) = preparers(question).find { !settled?(it) }
        def answerable?(question) = preparer(question).nil?

        def preparers(question)
            pending = rows(:question_pictures, :question_id, question)
                      .filter_map { it[:pending_id] }
            [question[:by_id], *pending].compact.map { piece(it) }
        end

        # The options as "LABEL = effect; cost" strings, the shape the
        # picker grammar reads.
        def options(question)
            rows(:question_choices, :question_id, question).map do |row|
                text = row[:label]
                text += " = #{row[:effect]}" if present?(row[:effect])
                text += "; #{row[:cost]}" if present?(row[:cost])
                text
            end
        end

        def items(question)
            rows(:question_items, :question_id, question).map { it[:text] }
        end

        # The inbox entries not taken yet, malformed ones included.
        def pending_entries = snapshot.inbox_entries.reject { it[:taken_id] }

        # {"O3" => ms, "P4:commit" => ms}: when each answerable question
        # and each awaited word started waiting on the user.
        def asked_since
            raise ArgumentError, "asked_since needs the events" unless @activity
            @activity.asked_since(self)
        end

        def present?(text) = !text.to_s.strip.empty?

        private

        def links(piece, kind)
            rows(:piece_links, :piece_id, piece).select { it[:kind] == kind }
        end

        def rows(table, key, owner)
            snapshot[table].select { it[key] == owner[:id] }
                           .sort_by { [it[:position], it[:id]] }
        end

        # What the events say of one ledger's rows: when each piece was
        # last touched (its row, or one of its rows in the piece tables),
        # when each row was inserted, when each piece last became settled.
        class Activity
            PIECE_TABLES = Snapshot::PIECE_TABLES.map(&:to_s).freeze

            def self.read(db, snapshot)
                rows = db[:event_rows].join(:events, id: :event_id)
                                      .where(ledger_id: snapshot.ledger_id)
                                      .order(Sequel[:events][:id])
                                      .select_map(%i[at tbl row_id before
                                                     after])
                new(rows)
            end

            attr_reader :touched

            # ROWS: [[at, tbl, row_id, before JSON, after JSON]] in event
            # order.
            def initialize(rows)
                @touched = {}
                @inserted = {}
                @settled = {}
                rows.each do |at, tbl, row_id, before, after|
                    note(at, tbl, row_id, parse(before), parse(after))
                end
            end

            def inserted(table, id) = @inserted[[table.to_s, id]]
            def settled_at(piece) = @settled[piece[:id]]

            # {"O3" => ms, "P4:commit" => ms} for DERIVE's ledger: the later
            # of a question's insert and its preparer settled, while it is
            # answerable; the insert of an awaits row.
            def asked_since(derive)
                questions_since(derive).merge(words_since(derive))
            end

            private

            def questions_since(derive)
                derive.open_questions.select { derive.answerable?(it) }
                      .to_h do |question|
                    times = [inserted(:questions, question[:id]),
                             *derive.preparers(question).map { settled_at(it) }]
                    [derive.qref(question), times.max]
                end
            end

            def words_since(derive)
                derive.pieces.flat_map do |piece|
                    derive.awaits_rows(piece).map do |row|
                        ["#{derive.ref(piece)}:#{row[:word]}",
                         inserted(:piece_awaits, row[:id])]
                    end
                end.to_h
            end

            def parse(json) = json && JSON.parse(json)

            def note(at, tbl, row_id, before, after)
                @inserted[[tbl, row_id]] ||= at if before.nil?
                piece_id = owner(tbl, row_id, before || after)
                @touched[piece_id] = at if piece_id
                settle(at, row_id, before, after) if tbl == "pieces"
            end

            def owner(tbl, row_id, row)
                return row_id if tbl == "pieces"
                row["piece_id"] if PIECE_TABLES.include?(tbl)
            end

            def settle(at, row_id, before, after)
                now = SETTLED.include?(after&.fetch("status"))
                was = SETTLED.include?(before&.fetch("status"))
                @settled[row_id] = at if now && !was
            end
        end

        # The status line `ledger status` prints, with
        # `stalled:` after blocked (U14). The beat's `unchanged ×N` is
        # the check command's to append (StatusLine.beat).
        class StatusLine
            # -> [count, line] for a check that beats: the count goes back
            # to 0 when the line moved since BEAT_LINE.
            def self.beat(line, beat_line, beat_count)
                count = line == beat_line ? beat_count + 1 : 0
                [count, count.zero? ? line : "#{line} · unchanged ×#{count}"]
            end

            def initialize(derive)
                @derive = derive
            end

            def to_s
                parts = [criteria, pieces, *states, *waiting, *viewer]
                parts << "done: propose close" if done?
                "Status — #{parts.join(" · ")}"
            end

            private

            def criteria
                all = @derive.criteria
                "criteria #{all.count { it[:mark] != " " }}/#{all.size}"
            end

            def pieces
                live = @derive.pieces.reject { it[:status] == "dropped" }
                kept = live.count { it[:status] == "kept" }
                verified = live.count { it[:status] == "verified" }
                text = "pieces #{verified}/#{live.size - kept} verified"
                kept.zero? ? text : "#{text}, #{kept} kept"
            end

            def states
                [named("out") { it[:status] == "out" },
                 named("back") { it[:status] == "back" },
                 named("blocked") { it[:status] == "blocked" },
                 named("stalled") { @derive.stalled?(it) }].compact
            end

            def named(label, &)
                ids = @derive.pieces.select(&).map { @derive.ref(it) }
                "#{label}: #{ids.join(", ")}" unless ids.empty?
            end

            def waiting
                [clause("waiting on you", ready),
                 clause("being prepared", preparing),
                 clause("your word", words)].compact
            end

            def clause(label, ids) = ("#{label}: #{ids.join(", ")}" if ids.any?)

            def ready
                @derive.open_questions.select { @derive.answerable?(it) }
                       .map { @derive.qref(it) }
            end

            def preparing
                @derive.open_questions.filter_map do |question|
                    piece = @derive.preparer(question) or next
                    "#{@derive.qref(question)} (#{@derive.ref(piece)})"
                end
            end

            def words
                @derive.pieces.filter_map do |piece|
                    next if @derive.awaits(piece).empty?
                    "#{@derive.ref(piece)} (#{@derive.awaits_label(piece)})"
                end
            end

            # Every entry has an N<n>, a malformed one too (the importer
            # numbers each line), so each pending one is named.
            def viewer
                ids = @derive.pending_entries.map { "N#{it[:n]}" }
                [clause("from the viewer", ids)].compact
            end

            def done?
                @derive.pending_entries.empty? &&
                    @derive.open_questions.empty? &&
                    Checks.failures(@derive.snapshot, final: true).empty?
            end
        end
    end
end

require "ledger/checks/runner"
