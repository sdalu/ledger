# frozen_string_literal: true

module Ledger
    # The rows that belong to one ledger, in every table that holds
    # them: counted for a dry run, deleted for a purge. Each entry is a
    # table, the column tying it to its owner, and that owner: nil for
    # the ledger itself, else the table of the ledger's own rows the
    # column points into. The order is the delete order, children first,
    # so no row ever points at a missing one.
    class Purge
        # KIDS, then OWNER itself, as TABLES lists them.
        def self.owned(owner, kids)
            column = :"#{owner.to_s.chomp("s")}_id"
            [*kids.map { [it, column, owner] }, [owner, :ledger_id, nil]]
        end

        # The tables whose rows hang from one of the ledger's own tables,
        # by that table's id: the column is the owner's name, singular
        # (pieces: piece_id).
        CHILDREN = {
            assumptions: %i[assumption_links assumption_sees],
            questions: %i[question_choices question_items question_pictures
                          question_sees],
            pieces: %i[piece_assessments piece_awaits piece_briefs piece_commits
                       piece_criteria piece_gates piece_links piece_pictures
                       piece_reports piece_returns piece_scopes]
        }.freeze

        # The tables with a ledger_id column of their own, after the
        # rows that point at them.
        OWN = %i[links pictures noticed inbox_entries decisions facts
                 criteria constraints goals counters session_ledgers
                 wakes outcomes].freeze

        TABLES = [
            *CHILDREN.flat_map { |owner, kids| owned(owner, kids) },
            *OWN.map { [it, :ledger_id, nil] },
            *owned(:events, %i[event_rows]),
            [:ledgers, :id, nil]
        ].freeze

        def initialize(db, id)
            @db = db
            @id = id
        end

        # -> { table => rows } for every table, zero counts included,
        # then the blobs that go with the ledger's pictures.
        def counts
            TABLES.to_h { |table, *spec| [table, rows(table, *spec).count] }
                  .merge(picture_blobs: blobs.count)
        end

        # Deletes every row counted, in one transaction the caller holds;
        # -> the counts. A piece's builds_id points at a question, which
        # goes before the pieces: cleared first, the cycle is broken. The
        # blobs are named before the pictures go, and deleted after them,
        # which point at them.
        def delete
            @db[:pieces].where(ledger_id: @id).exclude(builds_id: nil)
                        .update(builds_id: nil)
            gone = blobs.select_map(:sha256)
            TABLES.to_h { |table, *spec| [table, rows(table, *spec).delete] }
                  .merge(picture_blobs: @db[:picture_blobs]
                                            .where(sha256: gone).delete)
        end

        private

        # The blobs of the ledger's pictures that no other ledger's
        # picture points to: a content placed in two ledgers stays.
        def blobs
            pictures = @db[:pictures].select(:sha256)
            @db[:picture_blobs]
                .where(sha256: pictures.where(ledger_id: @id))
                .exclude(sha256: pictures.exclude(ledger_id: @id))
        end

        def rows(table, column, owner)
            return @db[table].where(column => @id) unless owner

            ids = @db[owner].where(ledger_id: @id).select(:id)
            @db[table].where(column => ids)
        end
    end
end
