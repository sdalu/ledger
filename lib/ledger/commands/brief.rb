# frozen_string_literal: true

require "json"

require "ledger/piece_brief"

module Ledger
    module Commands
        # `brief PATH P<n>`: what a brief for the piece is built from, as
        # one JSON object (PieceBrief), read from the journal; nothing
        # written, no beat counted.
        class Brief < CLI::Command
            USAGE = "PATH ID"
            SYNOPSIS = "PATH P<n>"
            SUMMARY = "what a brief for a piece is built from, as JSON: the " \
                      "piece, goals, constraints, facts, the question it " \
                      "builds, the user's decisions behind it"
            ID = /\AP([1-9]\d*)\z/

            private

            def run(path, id)
                ledger = journal.ledger(path)[:id]
                piece = piece(path, ledger, id)
                document = PieceBrief.new(journal.db, ledger, piece).to_h
                @out.puts JSON.pretty_generate(document)
                0
            end

            # The piece row ID names, refused when it names none.
            def piece(path, ledger, id)
                n = ID.match(id)&.[](1) or refuse("the target is P<n>")
                row = journal.db[:pieces].where(ledger_id: ledger,
                                                n: n.to_i).first
                row or refuse("no #{id} under Pieces in #{Address.parse(path)}")
            end
        end
    end
end
