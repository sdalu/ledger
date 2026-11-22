# frozen_string_literal: true

module Ledger
    module Checks
        # links: what the foreign keys cannot say. A link's target row
        # is in its `to_kind` table and in this ledger, and the pieces'
        # `after` never loops.
        module Links
            # Their `check --fix-hints` lines, merged into HINTS.
            HINTS = {
                "links" =>
                    "every link names a row of this ledger and `after` never " \
                    "loops; `bin/ledger piece PATH P<n> --after P3,P5`"
            }.freeze

            TABLES = { "X" => :decisions, "O" => :questions, "F" => :facts,
                       "C" => :constraints, "P" => :pieces }.freeze

            module_function

            def problems(derive) = targets(derive) + loops(derive)

            def targets(derive)
                snapshot = derive.snapshot
                snapshot.links.filter_map do |link|
                    next if row(snapshot, link[:to_kind], link[:to_row])
                    "#{from(snapshot, link)} (#{link[:kind]}: no " \
                        "#{link[:to_kind]} row #{link[:to_row]} in this ledger)"
                end
            end

            def row(snapshot, kind, id)
                snapshot[TABLES.fetch(kind)].find { it[:id] == id }
            end

            # The link's source as its visible id, or its row when even
            # that is not this ledger's.
            def from(snapshot, link)
                kind = link[:from_kind]
                source = row(snapshot, kind, link[:from_row])
                return "#{kind}#{source[:n]}" if source
                "#{kind} row #{link[:from_row]}"
            end

            # "after: loops through P1, P2" when the after graph has a
            # cycle; the ids on it in n order.
            def loops(derive)
                graph = derive.pieces.to_h do |piece|
                    [piece[:id], derive.after(piece).map { it[:id] }]
                end
                on = Cycle.new(graph).members
                return [] if on.empty?
                ids = on.map { derive.piece(it) }.sort_by { it[:n] }
                        .map { derive.ref(it) }
                ["after: loops through #{ids.join(", ")}"]
            end

            # The nodes on a cycle of a graph {node => [nodes it waits for]},
            # by depth-first search.
            class Cycle
                def initialize(graph)
                    @graph = graph
                    @state = {}
                    @on = []
                end

                def members
                    @graph.each_key { visit(it, [it]) unless @state[it] }
                    @on.uniq
                end

                private

                def visit(node, path)
                    @state[node] = :open
                    @graph.fetch(node, []).each do |next_node|
                        case @state[next_node]
                        when :open
                            @on.concat(path[path.index(next_node)..])
                        when nil then visit(next_node, path + [next_node])
                        end
                    end
                    @state[node] = :done
                end
            end
        end
    end
end
