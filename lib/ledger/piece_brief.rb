# frozen_string_literal: true

require "ledger/piece_facts"
require "ledger/text/pointer"

module Ledger
    # What a brief for one piece is built from, read from the journal and
    # nothing written: the piece, the goals it serves, the constraints,
    # the facts that bear on it (PieceFacts), the question it builds and
    # the decisions by user that led to it.
    #
    #     Ledger::PieceBrief.new(db, ledger_id, piece_row).to_h
    #     # => {piece: {...}, goals: [...], constraints: [...], facts: [...],
    #     #     builds: {...} or nil, answers: [...]}
    class PieceBrief
        def initialize(db, ledger_id, piece)
            @db = db
            @ledger_id = ledger_id
            @piece = piece
        end

        def to_h
            { piece:, goals:, constraints:,
              facts: PieceFacts.new(@db, @ledger_id, @piece).facts,
              builds:, answers: }
        end

        private

        def piece
            { id: "P#{@piece[:n]}", title: @piece[:title],
              what: @piece[:detail], done_when: @piece[:done_when],
              route: route }
        end

        # The route as the piece line writes it; a kept piece's reason.
        def route
            return "kept: #{@piece[:kept_reason]}" if @piece[:kept_reason]
            return "peer: #{@piece[:peer]}" if @piece[:peer]

            skills = ", skills: #{@piece[:skills]}" if @piece[:skills]
            "#{@piece[:model]}, effort: #{@piece[:effort]}#{skills}"
        end

        # Every Goal block not marked done; the latest when all are.
        def goals
            rows = own(:goals).order(:n).all
            active = rows.select { it[:done_at].nil? }
            rows = active.empty? ? rows.last(1) : active
            rows.map do |row|
                { id: "G#{row[:n]}", title: row[:title], short: row[:short],
                  quote: row[:quote] }
            end
        end

        def constraints
            own(:constraints).order(:n).map do |row|
                { id: "C#{row[:n]}", quote: row[:quote],
                  where: Text::Pointer.where(row[:text], row[:quote]) }
            end
        end

        # The question the piece builds, the decision answering it and
        # its words; both nil while the question is open.
        def builds
            question = @db[:questions].where(id: @piece[:builds_id]).first or
                return
            decision = answer(question)
            { question: "O#{question[:n]}",
              decision: decision && "X#{decision[:n]}",
              text: decision&.dig(:body) }
        end

        def answer(question)
            from = @db[:links].where(ledger_id: @ledger_id, kind: "answers",
                                     to_kind: "O", to_row: question[:id])
                              .get(:from_row) or return
            @db[:decisions].where(id: from).first
        end

        # The decisions by user with a led_to edge to the piece.
        def answers
            rows = @db[:links].where(ledger_id: @ledger_id, kind: "led_to",
                                     to_kind: "P", to_row: @piece[:id])
                              .select(:from_row)
            @db[:decisions].where(id: rows, by: "user").order(:n).map do |row|
                { id: "X#{row[:n]}", date: row[:date], text: row[:body] }
            end
        end

        def own(table) = @db[table].where(ledger_id: @ledger_id)
    end
end
