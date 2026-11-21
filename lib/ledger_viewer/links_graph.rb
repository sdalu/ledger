# frozen_string_literal: true

require "json"

module LedgerViewer
    # The data of the links page (views/ledger/links.erb): from a piece or a
    # decision, back through the links of a ledger's JSON v1 document to the
    # words that started it, and forward to what it led to.
    #
    #     view = LinksGraph.call(document, "P7")
    #     view.start    # the Node asked for
    #     view.back     # its reasons, nested: led-to, answers, replaces,
    #                   # rests-on, down to a question or the user's words
    #     view.forward  # what came out of it, nested
    #
    # The document is what Ledger::Read.ledger returns (symbol keys) or what
    # Ledger::Read.parse returns (string keys).
    module LinksGraph
        class Error < StandardError; end

        # An id the page cannot start from: only a piece (P) or a decision (X)
        # has a page.
        class NotStartable < Error; end

        # An id of no piece and no decision of the document.
        class Unknown < Error; end

        # One item of the lineage. kind is the id's letter; title, text,
        # quote, by, date, status, note and state are what the item is,
        # nil where it has none; user_words is true when `text` or `quote`
        # is the user's own wording, verbatim. via says how the item
        # relates to the one above it (nil for the start); also lists
        # [label, ids] pairs that are links of the item's own (after, for,
        # prepared by), not walked; next_nodes are the items below, nested.
        # Every link's target is an item of the document: the journal
        # holds no edge to a row it lacks.
        Node = Data.define(:id, :kind, :title, :text, :quote, :by, :date,
                           :status, :note, :state, :user_words, :via, :also,
                           :next_nodes) do
            def root? = next_nodes.empty?
        end

        View = Data.define(:ledger, :start, :back, :forward)

        # What the next item is, said from the item above it, going back
        # (the item below led to it, was answered by it) and going forward.
        BACK = { "led_to" => "led to it", "answers" => "was answered by it",
                 "replaces" => "was replaced by it",
                 "rests_on" => "is relied on by it" }.freeze
        FORWARD = { "led_to" => "led to", "answers" => "answered by",
                    "replaces" => "replaced by" }.freeze

        module_function

        def call(document, id)
            doc = symbolize(document)
            index = Index.new(doc)
            raise NotStartable, "#{id}: only P and X have a page" unless
                id.match?(/\A[PX]\d+\z/)
            raise Unknown, "#{id}: not in this ledger" unless index.known?(id)

            walk = Walk.new(index)
            View.new(ledger: doc.dig(:ledger, :address),
                     start: walk.node(id), back: walk.back(id),
                     forward: walk.forward(id))
        end

        # A Read.parse document has string keys; nothing else is converted.
        def symbolize(document)
            return document if document.key?(:schema)

            JSON.parse(JSON.generate(document), symbolize_names: true)
        end

        # The items by id and the links, read once.
        class Index
            def initialize(doc)
                @links = doc.fetch(:links)
                @items = {}
                %i[decisions facts constraints pieces questions
                   closed_questions].each do |table|
                    doc.fetch(table).each { @items[it.fetch(:id)] = it }
                end
                @closed = doc.fetch(:closed_questions).to_set { it[:id] }
            end

            def known?(id) = @items.key?(id)
            def item(id) = @items.fetch(id)
            def closed?(id) = @closed.include?(id)

            # The ids that point at `id` by `kind`, and the ones `id`
            # points at.
            def from(kind, id) = edges(kind, :to, id, :from)
            def to(kind, id) = edges(kind, :from, id, :to)

            private

            def edges(kind, match, id, give)
                @links.select { it[:kind] == kind && it[match] == id }
                      .map { it[give] }
            end
        end

        # The two walks, over one Index.
        class Walk
            KINDS = { "P" => "piece", "X" => "decision", "O" => "question",
                      "F" => "fact", "C" => "constraint" }.freeze

            def initialize(index)
                @index = index
            end

            def back(id)
                parents(id).map { |kind, found| node(found, BACK[kind], :back) }
            end

            def forward(id)
                children(id).map do |kind, found|
                    node(found, FORWARD.fetch(kind), :forward)
                end
            end

            def node(id, via = nil, way = nil)
                below = way ? send(way, id) : []
                Node.new(id:, kind: id[0], via:, next_nodes: below,
                         **fields(id, @index.item(id)))
            end

            private

            # [edge kind, id] of the items a node was led by, going back.
            def parents(id)
                [*@index.from("led_to", id).map { ["led_to", it] },
                 *@index.to("answers", id).map { ["answers", it] },
                 *@index.to("replaces", id).map { ["replaces", it] },
                 *@index.to("rests_on", id).map { ["rests_on", it] }]
            end

            def children(id)
                [*@index.to("led_to", id).map { ["led_to", it] },
                 *@index.from("answers", id).map { ["answers", it] },
                 *@index.from("replaces", id).map { ["replaces", it] }]
            end

            def fields(id, item)
                base = { title: nil, text: nil, quote: nil, by: nil,
                         date: nil, status: nil, note: nil, state: nil,
                         user_words: false, also: [] }
                base.merge(send(:"of_#{KINDS.fetch(id[0])}", id, item))
            end

            def of_piece(_id, item)
                { title: item[:title], status: item[:status],
                  state: piece_state(item),
                  also: also("after" => item[:after], "serves" => item[:for]) }
            end

            def piece_state(item)
                return "is-done" if item[:settled]
                return "is-fail" if item[:status] == "blocked"

                "is-flight" if %w[out back].include?(item[:status])
            end

            def of_decision(_id, item)
                by = item[:by]
                { text: item[:body], by:, date: item[:date],
                  note: item[:note], user_words: by == "user" }
            end

            def of_question(id, item)
                { title: item[:title], date: item[:closed_at],
                  state: @index.closed?(id) ? "is-done" : "is-ask",
                  also: also("prepared by" => [item[:by]]) }
            end

            def of_fact(_id, item)
                { text: item[:text], note: item[:pointer] }
            end

            def of_constraint(_id, item)
                { text: item[:text], quote: item[:quote], user_words: true }
            end

            # after, for and prepared-by: links a node carries, never walked.
            def also(labelled)
                labelled.map { |label, ids| [label, ids.compact] }
                        .reject { |_, ids| ids.empty? }
            end
        end
    end
end
