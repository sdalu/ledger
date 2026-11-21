# frozen_string_literal: true

require "json"

module Ledger
    # A ledger closed unfinished, `close PATH --abandon` (docs/journal.md,
    # section 4): no column of its own, its closing event's argv holds the
    # flag. In the close's own write, every piece still open is dropped
    # and every open question closed by a decision by user, so the
    # history says what was left and nothing reads as still to do.
    #
    #     Ledger::Abandon.write(change, db)   # inside the close's write
    #     Ledger::Abandon.ids(db, [3, 4])     # => [4]
    module Abandon
        FLAG = "--abandon"
        # The pieces an abandon drops: those not finished nor dropped.
        OPEN = %w[planned out back blocked].freeze
        # The decision that closes each open question.
        WORDS = "abandoned with the ledger"

        module_function

        def write(change, db, date: Time.now.strftime("%F"))
            id = change.ledger_id
            db[:pieces].where(ledger_id: id, status: OPEN).select_map(:id)
                       .each { drop(change, db, it) }
            db[:questions].where(ledger_id: id, closed_at: nil).order(:n).all
                          .each { close_question(change, it, date) }
        end

        # PIECE dropped as `word --word drop` drops one: it awaits
        # nothing after, its awaits and scope rows deleted.
        def drop(change, db, piece)
            change.status(piece, "dropped")
            %i[piece_awaits piece_scopes].each do |table|
                db[table].where(piece_id: piece).select_map(:id)
                         .each { change.delete(table, it) }
            end
        end

        # QUESTION closed as `answer` closes one: a decision by user, the
        # X answers O edge, `closed_at`.
        def close_question(change, question, date)
            ref = "O#{question[:n]}"
            n = change.next_id("X")
            change.insert(:decisions, n:, date:, body: "#{ref}: #{WORDS}",
                                      by: "user", subject: ref)
            change.update(:questions, question[:id], closed_at: Write.now)
            change.link("answers", "X#{n}", ref)
        end

        # The ledgers among LEDGER_IDS closed by an abandon: a close is
        # written once and never undone, its event the one to read.
        def ids(db, ledger_ids)
            db[:events].where(ledger_id: ledger_ids, command: "close")
                       .select_map(%i[ledger_id argv])
                       .filter_map { |id, argv| id if flag?(argv) }.uniq
        end

        def abandoned?(db, ledger_id) = ids(db, [ledger_id]).any?

        # How the ledger ROW closed, as `show` ends a closed one:
        # `abandoned: TIME` or `closed: TIME`; nil while it is live.
        def line(db, row)
            at = row[:closed_at] or return

            word = abandoned?(db, row[:id]) ? "abandoned" : "closed"
            "#{word}: #{Render::Json.time(at)}"
        end

        def flag?(argv) = JSON.parse(argv).include?(FLAG)
    end
end
