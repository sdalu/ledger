# frozen_string_literal: true

require "digest"
require "json"

require "ledger/derive"
require "ledger/render/markdown"
require "ledger/text/pointer"

module Ledger
    module Render
        # A ledger as JSON v1 (docs/journal.md, section 6): one Hash whose
        # first key is `schema`, the second `kind`, the rest in the order
        # of the note's table, so two renders of one ledger compare equal
        # as whole documents. Every derived value comes from the Derive.
        #
        #     doc = Ledger::Render::Json.ledger(snapshot, derive, context)
        #     Ledger::Render::Json.generate(doc)   # the text
        class Json
            SCHEMA = 1
            # A Goal block's own columns, between its id and its done mark.
            GOAL = %i[stamp date revised title short context quote].freeze

            # What the rows alone do not say: UPDATED_AT (ms), SIZES
            # {picture id => bytes}, EVENTS {event id => {at:, actor:}}
            # for the briefs, the returns and the takes, CLAIMS {piece id
            # => ms}.
            Context = Data.define(:updated_at, :sizes, :events, :claims)

            def self.ledger(snapshot, derive, context)
                new(snapshot, derive, context).ledger
            end

            # One ledger of the index: what its Snapshot and Derive say, and
            # UPDATED_AT in ms.
            Part = Data.define(:snapshot, :derive, :updated_at)

            # {schema, kind: "index", ledgers}: live ledgers first, then by
            # updated_at, newest first.
            def self.index(parts) = Index.new(parts).call

            def self.generate(document) = JSON.generate(document)

            # Milliseconds since the epoch as ISO 8601 in local time with
            # the offset; nil stays nil.
            def self.time(millis)
                return unless millis

                Time.at(millis / 1000, millis % 1000, :millisecond)
                    .strftime("%FT%T%:z")
            end

            def initialize(snapshot, derive, context)
                @snapshot = snapshot
                @derive = derive
                @context = context
                @markdown = Markdown.new(snapshot)
            end

            def ledger
                { schema: SCHEMA, kind: "ledger", ledger: header,
                  goals: goals, **items, links: links,
                  closed_questions: questions.closed, pictures: pictures,
                  pieces: pieces, questions: questions.open, refs: refs,
                  **tail }
            end

            private

            # noticed, inbox, asked, status and fails.
            def tail
                { noticed: @snapshot.noticed.map { it[:line] },
                  inbox: inbox, asked: asked, status: status_line,
                  fails: fails }
            end

            def header
                row = @snapshot.ledger
                address = Address.new(place: row[:place], name: row[:name])
                { id: row[:id], address: address.to_s,
                  **row.slice(:place, :name, :project),
                  url_id: Digest::SHA1.hexdigest(address.to_s)[0, 10],
                  updated_at: self.class.time(@context.updated_at),
                  closed_at: self.class.time(row[:closed_at]) }
            end

            def goals
                @snapshot.goals.map do |row|
                    { id: "G#{row[:n]}", **row.slice(*GOAL),
                      done: !row[:done_at].nil?, **row.slice(:done_evidence) }
                end
            end

            def items = Items.new(@snapshot, @derive, @markdown).call

            def links = Links.new(@snapshot).call

            def pictures
                @snapshot.pictures.group_by { it[:name] }.map do |name, rows|
                    { name:, files: rows.map { file(it) } }
                end
            end

            def file(row)
                { path: row[:path], type: row[:type],
                  size: @context.sizes.fetch(row[:id]) }
            end

            def pieces
                renderer = Pieces.new(@snapshot, @derive, @context, @markdown)
                @snapshot.pieces.map { renderer.call(it) }
            end

            def questions
                @questions ||= Questions.new(@snapshot, @derive, @markdown)
            end

            # {"C" => {"C1" => {kind:, line:}}, ...} in kind then row order.
            def refs
                { "C" => :constraints, "D" => :criteria, "F" => :facts,
                  "P" => :pieces, "X" => :decisions }.flat_map do |kind, table|
                    @snapshot[table].map do |row|
                        id = "#{kind}#{row[:n]}"
                        [id, { kind:, line: @markdown.line(id) }]
                    end
                end.to_h
            end

            def inbox = Inbox.new(@context).call(@snapshot.inbox_entries)

            def asked
                @derive.asked_since.transform_values { self.class.time(it) }
            end

            def status_line = Derive::StatusLine.new(@derive).to_s

            def fails
                Checks.failures(@snapshot).map do |name, detail|
                    { name:, detail: }
                end
            end
        end

        class Json
            # The one-line items: criteria, constraints, facts, assumptions
            # and decisions, each its id, its columns, what it derives and
            # the line `show` prints.
            class Items
                def initialize(snapshot, derive, markdown)
                    @snapshot = snapshot
                    @derive = derive
                    @markdown = markdown
                end

                def call
                    { criteria: lined("D", :criteria,
                                      %i[mark text evidence why]),
                      constraints: lined("C", :constraints, %i[text quote],
                                         &Text::Pointer.method(:of_constraint)),
                      facts: lined("F", :facts, %i[text pointer],
                                   &Text::Pointer.method(:of_fact)),
                      assumptions: lined("A", :assumptions,
                                         %i[text check state]) { assumed(it) },
                      decisions: lined("X", :decisions,
                                       %i[date body by note subject]) }
                end

                private

                # The fact that settled it, what it rests on, what rests
                # on it.
                def assumed(row)
                    { fact: @derive.settled_by(row),
                      see: @derive.assumption_sees(row),
                      for: @derive.resting(row) }
                end

                # A block adds the columns it derives from the row, after
                # the row's own.
                def lined(kind, table, columns)
                    @snapshot[table].map do |row|
                        { id: "#{kind}#{row[:n]}", **row.slice(*columns),
                          **(block_given? ? yield(row) : {}),
                          line: @markdown.line("#{kind}#{row[:n]}") }
                    end
                end
            end
        end

        class Json
            # The links as `{kind, from, to}`, visible ids at both ends.
            class Links
                TABLES = { "X" => :decisions, "O" => :questions,
                           "F" => :facts, "C" => :constraints,
                           "P" => :pieces }.freeze

                def initialize(snapshot)
                    @snapshot = snapshot
                    @numbers = TABLES.transform_values do |table|
                        snapshot[table].to_h { [it[:id], it[:n]] }
                    end
                end

                def call
                    @snapshot.links.map do |row|
                        { kind: row[:kind],
                          from: id(row[:from_kind], row[:from_row]),
                          to: id(row[:to_kind], row[:to_row]) }
                    end
                end

                private

                def id(kind, row_id)
                    "#{kind}#{@numbers.fetch(kind).fetch(row_id)}"
                end
            end
        end

        class Json
            # The index of all ledgers, live then closed.
            class Index
                def initialize(parts) = @parts = parts

                def call
                    { schema: SCHEMA, kind: "index",
                      ledgers: ordered.map { entry(it) } }
                end

                private

                def ordered
                    @parts.sort_by do |part|
                        [part.snapshot.ledger[:closed_at] ? 1 : 0,
                         -part.updated_at, part.snapshot.ledger_id]
                    end
                end

                def entry(part)
                    snapshot = part.snapshot
                    row = snapshot.ledger
                    { id: row[:id], address: address(row),
                      project: row[:project], **goal(snapshot),
                      created_at: Json.time(row[:created_at]),
                      updated_at: Json.time(part.updated_at),
                      closed_at: Json.time(row[:closed_at]),
                      **derived(part.derive) }
                end

                def address(row)
                    Address.new(place: row[:place], name: row[:name]).to_s
                end

                # The title and the short form of the last goal.
                def goal(snapshot)
                    row = snapshot.goals.last || {}
                    { title: row[:title], short: row[:short] }
                end

                def derived(derive)
                    { status: Derive::StatusLine.new(derive).to_s,
                      waiting: waiting(derive), words: words(derive),
                      pending: pending(derive) }
                end

                def waiting(derive)
                    derive.open_questions.select { derive.answerable?(it) }
                          .map { derive.qref(it) }
                end

                def words(derive)
                    derive.pieces.reject { derive.awaits(it).empty? }
                          .map { derive.ref(it) }
                end

                def pending(derive)
                    derive.pending_entries.map { "N#{it[:n]}" }
                end
            end
        end

        class Json
            # The inbox entries.
            class Inbox
                def initialize(context) = @context = context

                def call(rows) = rows.map { entry(it) }

                private

                def entry(row)
                    taken = @context.events[row[:taken_id]]
                    { id: "N#{row[:n]}", at: row[:at],
                      ref: row[:ref], payload: row[:payload],
                      malformed: row[:malformed], taken: !taken.nil?,
                      taken_at: Json.time(taken&.fetch(:at)),
                      taken_by: taken&.fetch(:actor) }
                end
            end
        end

        class Json
            # The pieces of a ledger as their JSON objects.
            class Pieces
                def initialize(snapshot, derive, context, markdown)
                    @derive = derive
                    @context = context
                    @markdown = markdown
                    @briefs = snapshot.piece_briefs.group_by { it[:piece_id] }
                    @criteria = Refs.group(snapshot.piece_criteria, :piece_id)
                    @returns = Refs.group(snapshot.piece_returns, :piece_id)
                end

                def call(piece)
                    { id: "P#{piece[:n]}", **head(piece), **links(piece),
                      **prose(piece), **state(piece), brief: brief(piece),
                      criteria: criteria(piece), returns: returns(piece),
                      pictures: @derive.pictures(piece).map do |row|
                          row.slice(:role, :name)
                      end,
                      no_picture: piece[:no_picture],
                      line: @markdown.line("P#{piece[:n]}") }
                end

                private

                def head(piece)
                    { status: piece[:status], kept_reason: piece[:kept_reason],
                      until: piece[:until], route: route(piece),
                      route_text: route_text(piece),
                      title: piece[:title], detail: piece[:detail],
                      done_when: piece[:done_when], evidence: piece[:evidence] }
                end

                def route(piece)
                    return unless piece[:peer] || piece[:model]

                    { model: piece[:model], effort: piece[:effort],
                      skills: piece[:skills], peer: piece[:peer] }
                end

                def route_text(piece)
                    return "peer: #{piece[:peer]}" if piece[:peer]
                    return unless piece[:model]

                    skills = ", skills: #{piece[:skills]}" if piece[:skills]
                    "#{piece[:model]}, effort: #{piece[:effort]}#{skills}"
                end

                def links(piece)
                    { after: @derive.after(piece).map { @derive.ref(it) },
                      for: @derive.serves(piece).map { "D#{it[:n]}" },
                      awaits: @derive.awaits(piece).map do |word, what|
                          { word:, what: }
                      end,
                      scope: @derive.scopes(piece).map do |row|
                          row.slice(:word, :text)
                      end,
                      rests_on_assumptions:
                          @derive.rests_on(piece).map { @derive.aref(it) } }
                end

                def prose(piece)
                    risk = piece[:risk]
                    { problem: piece[:problem],
                      risk: risk && { rating: piece[:risk_rating], text: risk },
                      plan: piece[:plan], verified_by: piece[:verified_by],
                      claim: claim(piece) }
                end

                def claim(piece)
                    return unless piece[:claimed_by]

                    { session: piece[:claimed_by],
                      since: Json.time(@context.claims[piece[:id]]) }
                end

                def state(piece)
                    { ready: @derive.ready?(piece),
                      stalled: @derive.stalled?(piece),
                      touched_at: Json.time(@derive.touched_at(piece)),
                      settled: @derive.settled?(piece) }
                end

                def brief(piece)
                    row = @briefs.fetch(piece[:id], []).max_by { it[:version] }
                    return unless row

                    { version: row[:version],
                      at: Json.time(@context.events.dig(row[:event_id], :at)) }
                end

                def criteria(piece)
                    @criteria.fetch(piece[:id], []).map do |row|
                        row.slice(:text, :mark, :evidence)
                    end
                end

                # Each time the piece went back to planned, oldest first.
                def returns(piece)
                    @returns.fetch(piece[:id], []).map do |row|
                        event = @context.events.fetch(row[:event_id])
                        { cause: row[:cause], from: row[:from_status],
                          at: Json.time(event[:at]), actor: event[:actor] }
                    end
                end
            end
        end

        class Json
            # The questions of a ledger as their JSON objects: the open ones
            # with their derived states, the closed ones with `closed_at`.
            class Questions
                SEES = { "C" => :constraint_id, "D" => :criterion_id,
                         "F" => :fact_id, "P" => :piece_id }.freeze

                def initialize(snapshot, derive, markdown)
                    @snapshot = snapshot
                    @derive = derive
                    @markdown = markdown
                    @refs = Refs.new(snapshot)
                    @asked = derive.asked_since
                    @groups = %i[choices sees pictures].to_h do |kind|
                        rows = snapshot[:"question_#{kind}"]
                        [kind, Refs.group(rows, :question_id)]
                    end
                end

                def open
                    @derive.open_questions.map { call(it) }
                end

                def closed
                    rows = @snapshot.questions.reject { it[:closed_at].nil? }
                    rows.sort_by { [it[:closed_at], it[:id]] }.map do |row|
                        call(row, closed: true)
                    end
                end

                private

                def call(question, closed: false)
                    { id: "O#{question[:n]}", **text(question),
                      **lists(question), **state(question, closed),
                      line: @markdown.line("O#{question[:n]}"),
                      **closing(question, closed) }
                end

                def closing(question, closed)
                    return {} unless closed

                    { closed_at: Json.time(question[:closed_at]) }
                end

                def text(question)
                    risk = question[:risk]
                    { title: question[:title], detail: question[:detail],
                      problem: question[:problem],
                      risk: risk && { rating: question[:risk_rating],
                                      text: risk },
                      recommend: question[:recommend] }
                end

                def lists(question)
                    { choices: choices(question),
                      items: @derive.items(question),
                      by: (@refs["P", question[:by_id]] if question[:by_id]),
                      see: sees(question), pictures: pictures(question),
                      rests_on_assumptions: @derive.question_rests_on(question)
                                                   .map { @derive.aref(it) } }
                end

                def choices(question)
                    rows = @groups[:choices].fetch(question[:id], [])
                    rows.zip(@derive.options(question)).map do |row, text|
                        { **row.slice(:label, :effect, :cost), text: }
                    end
                end

                def sees(question)
                    @groups[:sees].fetch(question[:id], []).map do |row|
                        kind, column = SEES.find { |_, col| row[col] }
                        @refs[kind, row[column]]
                    end
                end

                def pictures(question)
                    @groups[:pictures].fetch(question[:id], []).map do |row|
                        next { name: row[:name] } if row[:name]

                        { pending: @refs["P", row[:pending_id]] }
                    end
                end

                def state(question, closed)
                    piece = !closed && @derive.preparer(question)
                    since = !closed && @asked["O#{question[:n]}"]
                    { preparing: (@derive.ref(piece) if piece),
                      preparing_status: (piece[:status] if piece),
                      asked_since: (Json.time(since) if since) }
                end
            end
        end
    end
end
