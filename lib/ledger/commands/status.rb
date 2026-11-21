# frozen_string_literal: true

require "json"

module Ledger
    module Commands
        # `status PATH [--json]`: the status line, or the parts it is
        # made of as JSON v1.
        class Status < CLI::Command
            USAGE = "PATH"

            private

            def flags(parser) = parser.on("--json") { @opts[:json] = true }

            def run(path)
                snapshot = snapshot(path)
                line = status_line(snapshot)
                @out.puts @opts[:json] ? JSON.generate(document(snapshot,
                                                                line)) : line
                0
            end

            def document(snapshot, line)
                derive = Derive.read(journal.db, snapshot)
                { schema: Render::Json::SCHEMA, kind: "status", line:,
                  **counts(derive), **states(derive), **waiting(derive),
                  propose_close: line.end_with?("done: propose close") }
            end

            def counts(derive)
                live = derive.pieces.reject { it[:status] == "dropped" }
                kept = live.count { it[:status] == "kept" }
                { criteria: [derive.criteria.count { it[:mark] != " " },
                             derive.criteria.size],
                  pieces: { verified: live.count { it[:status] == "verified" },
                            live: live.size - kept, kept: } }
            end

            def states(derive)
                %w[out back blocked].to_h do |status|
                    [status.to_sym, refs(derive) { it[:status] == status }]
                end.merge(stalled: refs(derive) { derive.stalled?(it) })
            end

            def refs(derive, &) = derive.pieces.select(&).map { derive.ref(it) }

            def waiting(derive)
                open = derive.open_questions
                ready = open.select { derive.answerable?(it) }
                { waiting: ready.map { derive.qref(it) },
                  preparing: open.filter_map { preparing(derive, it) },
                  words: words(derive),
                  from_viewer: derive.pending_entries.map { "N#{it[:n]}" } }
            end

            def preparing(derive, question)
                piece = derive.preparer(question)
                [derive.qref(question), derive.ref(piece)] if piece
            end

            def words(derive)
                derive.pieces.filter_map do |piece|
                    words = derive.awaits(piece).map(&:first)
                    { piece: derive.ref(piece), words: } unless words.empty?
                end
            end
        end
    end
end
