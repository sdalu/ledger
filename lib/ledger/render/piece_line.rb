# frozen_string_literal: true

require "ledger/render/refs"
require "ledger/text/awaits"

module Ledger
    module Render
        # A piece as its line in the Markdown: `- P7 [status] route —
        # title: detail`, an obsolete one's `— obsoleted by P<n>`, then
        # the fields in the order `piece` writes them, `— no commit:
        # WHY`, `— commits: a1b2c3d, e4f5a6b`, `— picture: being redrawn
        # (WHY)` and `— picture: holds (WHY)`, then `— dispatched: N×
        # (last: …)` when a dispatch was announced (piece --announce).
        class PieceLine
            def initialize(snapshot, refs)
                @refs = refs
                @links = Refs.group(snapshot.piece_links, :piece_id)
                @awaits = Refs.group(snapshot.piece_awaits, :piece_id)
                @scopes = Refs.group(snapshot.piece_scopes, :piece_id)
                @assessed = Refs.group(snapshot.piece_assessments, :piece_id)
                @commits = Refs.group(snapshot.piece_commits, :piece_id)
            end

            def call(piece)
                line = "- P#{piece[:n]} [#{status(piece)}] #{head(piece)}" \
                       "#{obsoleted(piece)}"
                fields(piece).reduce(line) do |text, (name, value, tail)|
                    "#{text} — #{name}: #{value}#{tail}"
                end
            end

            private

            def status(piece)
                return piece[:status] unless piece[:status] == "kept"

                "kept: #{piece[:kept_reason]}"
            end

            def obsoleted(piece)
                id = piece[:obsoleted_by_id] or return

                " — obsoleted by #{@refs["P", id]}"
            end

            def head(piece)
                what = piece[:title]
                what = "#{what}: #{piece[:detail]}" if piece[:detail]
                route = route(piece)
                return "#{route} — #{what}" if route

                piece[:dash] ? "— #{what}" : what
            end

            def route(piece)
                return "peer: #{piece[:peer]}" if piece[:peer]
                return unless piece[:model]

                skills = ", skills: #{piece[:skills]}" if piece[:skills]
                "#{piece[:model]}, effort: #{piece[:effort]}#{skills}"
            end

            # [[name, value, tail]] of the fields the piece has, in order.
            def fields(piece)
                (first_fields(piece) + last_fields(piece))
                    .reject { |_, value,| value.nil? || value.empty? }
            end

            def first_fields(piece)
                [["until", piece[:until]],
                 ["problem", piece[:problem]], ["risk", piece[:risk]],
                 ["plan", piece[:plan]], ["scope", scope(piece)],
                 ["done when", piece[:done_when]], *links(piece),
                 ["awaits", awaits(piece)], ["evidence", piece[:evidence]]]
            end

            def last_fields(piece)
                [["no commit", piece[:no_commit]], ["commits", commits(piece)],
                 ["picture", redrawn(piece)], ["picture", holds(piece)],
                 ["dispatched", dispatched(piece)]]
            end

            # "2\u00D7 (last: sonnet, medium, stakes low, risk 2/10)": the
            # dispatches announced and the last one's assessment, what it
            # left out left out.
            def dispatched(piece)
                rows = @assessed.fetch(piece[:id], [])
                last = rows.last or return

                "#{rows.size}\u00D7 (last: #{assessment(last)})"
            end

            def assessment(row)
                axis = row[:axis] && [row[:axis], row[:axis_level]].compact
                risk = row[:risk_rating]&.then { "risk #{it}/10" }
                parts = [row[:model], row[:effort], axis&.join(" "), risk]
                parts.compact.join(", ")
            end

            def commits(piece)
                rows = @commits.fetch(piece[:id], [])
                rows.sort_by { it[:position] }.map { it[:sha] }.join(", ")
            end

            def redrawn(piece)
                why = piece[:picture_pending] or return

                "being redrawn (#{why})"
            end

            def holds(piece)
                why = piece[:picture_holds] or return

                "holds (#{why})"
            end

            def links(piece)
                %w[after for].map do |kind|
                    [kind, ids(piece, kind), Refs.tail(piece[:"#{kind}_tail"])]
                end
            end

            def ids(piece, kind)
                links = @links.fetch(piece[:id], [])
                links.select { it[:kind] == kind }.map { link_id(it) }
                     .join(", ")
            end

            def link_id(link)
                return @refs["P", link[:after_id]] if link[:after_id]

                @refs["D", link[:criterion_id]]
            end

            def awaits(piece)
                rows = @awaits.fetch(piece[:id], [])
                Text::Awaits.label(rows.map { [it[:word], it[:what]] })
            end

            def scope(piece)
                rows = @scopes.fetch(piece[:id], [])
                Text::Awaits.scope_text(rows.map { [it[:word], it[:text]] })
            end
        end
    end
end
