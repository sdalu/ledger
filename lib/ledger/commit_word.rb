# frozen_string_literal: true

require "ledger/text/awaits"

module Ledger
    # The user's commit word on a piece, read from the decisions `word`
    # files: a decision by user whose body is `P<n>: "WORDS"`, WORDS
    # naming commit, with a led_to edge to the piece. The edge's event
    # says who filed it.
    module CommitWord
        BODY = /\AP[1-9]\d*: "(?<words>[^"]*)"/

        module_function

        # The led_to links of SNAPSHOT that file a commit word on PIECE.
        def links(snapshot, piece)
            snapshot.links.select do |link|
                link[:kind] == "led_to" && link[:to_kind] == "P" &&
                    link[:to_row] == piece[:id] &&
                    commit?(decision(snapshot, link[:from_row]))
            end
        end

        # Whether PIECE was given its commit word.
        def given?(snapshot, piece) = links(snapshot, piece).any?

        def decision(snapshot, id)
            snapshot.decisions.find { it[:id] == id }
        end

        def commit?(row)
            return false unless row && row[:by] == "user"

            words = BODY.match(row[:body])&.[](:words).to_s
            Text::Awaits.split(words).map(&:strip).include?("commit")
        end
    end
end
