# frozen_string_literal: true

require "json"

require "ledger/inbox"

module Ledger
    module Commands
        # `survey [DIR] [--peer NAME] [--json]`: what a session with no goal
        # reads first, and nothing it writes: the live ledgers at DIR (the
        # current directory by default) or under it, each with its status
        # line and its pending inbox entries; with --peer, the pieces of any
        # live ledger routed `peer: NAME`. No heartbeat is counted and no
        # event is written.
        class Survey < CLI::Command
            USAGE = "[DIR]"
            SYNOPSIS = "[DIR] [--peer NAME]"
            SUMMARY = "read-only: the live ledgers at DIR or under it with " \
                      "status and pending entries, and the pieces routed " \
                      "peer: NAME"

            private

            def flags(parser)
                parser.on("--peer NAME", "also list the pieces routed " \
                                         "`peer: NAME`, as written") do |n|
                    @opts[:peer] = n
                end
                parser.on("--json", "JSON v1") { @opts[:json] = true }
            end

            def run(dir = ".")
                dir = File.expand_path(dir)
                found = journal.live_under(dir).map { entry(it) }
                peer = @opts[:peer]
                pieces = peer ? routed(peer) : nil
                if @opts[:json]
                    @out.puts JSON.generate(document(dir, found, peer, pieces))
                else
                    plain(dir, found, peer, pieces)
                end
                0
            end

            # One ledger: its address, its status line as `check --peek`
            # prints it, its pending entries as `inbox` prints them.
            def entry(address)
                snapshot = snapshot(address)
                pending = Ledger::Inbox.pending(snapshot).map do |row|
                    { id: "N#{row[:n]}", text: Ledger::Inbox.show(row) }
                end
                { address: address.to_s, status: status_line(snapshot),
                  inbox: pending }
            end

            # Every piece of every live ledger routed to NAME, as a ledger
            # address and the piece's Markdown line.
            def routed(name)
                journal.db[:ledgers].where(closed_at: nil)
                       .order(:place, :name).flat_map { routed_in(it, name) }
            end

            def routed_in(row, name)
                snapshot = Snapshot.read(journal.db, row[:id])
                address = Address.new(place: row[:place], name: row[:name])
                snapshot.pieces.select { it[:peer] == name }.map do |piece|
                    ref = "P#{piece[:n]}"
                    { ledger: address.to_s, id: ref,
                      line: Render::Markdown.line(snapshot, ref) }
                end
            end

            def plain(dir, found, peer, pieces)
                none = "survey: no live ledger at or under #{dir}"
                @out.puts(found.empty? ? none : found.map { text(it) }
                                                      .join("\n\n"))
                return unless peer

                @out.puts if found.any?
                plain_peer(peer, pieces)
            end

            def text(item)
                [item[:address], item[:status], *item[:inbox].map { it[:text] }]
                    .join("\n")
            end

            def plain_peer(peer, pieces)
                if pieces.empty?
                    @out.puts "peer: no piece routed peer: #{peer}"
                    return
                end
                @out.puts "pieces routed peer: #{peer}:"
                pieces.each { @out.puts "#{it[:ledger]}  #{it[:line]}" }
            end

            def document(dir, found, peer, pieces)
                { schema: Render::Json::SCHEMA, kind: "survey", dir:,
                  ledgers: found,
                  peer: peer && { name: peer, pieces: } }
            end
        end
    end
end
