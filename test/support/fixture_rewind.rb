# frozen_string_literal: true

# fixture_rewind.rb -- the browser checks' way back from a send, run by
# tests/browser/viewer.cjs as
#     bundle exec ruby test/support/fixture_rewind.rb mark ADDRESS
#     bundle exec ruby test/support/fixture_rewind.rb rewind ADDRESS E<n>
# on the test journal ($LEDGER_JOURNAL). `mark` prints the ledger's
# newest event id as E<n>. `rewind` deletes the inbox events after E<n>
# with the entries they filed, in one transaction, and puts the N
# counter back; it refuses when any later event is not an inbox event,
# so a rewind never hides a real change. A test aid: no command of
# bin/ledger takes a viewer's entry back.

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "ledger"

module FixtureRewind
    # The ledger's newest event, as E<n>.
    def self.mark(journal, address)
        id = journal.ledger(address)[:id]
        "E#{journal.db[:events].where(ledger_id: id).max(:id)}"
    end

    def self.rewind(journal, address, mark)
        raise Ledger::Refused, "not an event: #{mark}" unless
            mark.match?(/\AE\d+\z/)

        journal.transaction do
            ledger = journal.ledger(address)[:id]
            events = journal.db[:events].where(ledger_id: ledger)
                            .where(Sequel[:id] > mark[1..].to_i)
            refuse_others(events)
            delete(journal.db, ledger, events.select_map(:id))
        end
    end

    def self.refuse_others(events)
        other = events.exclude(command: "inbox").select_map(:command)
        return if other.empty?

        raise Ledger::Refused,
              "events after the mark are not all inbox: #{other.join(", ")}"
    end

    def self.delete(db, ledger, ids)
        rows = db[:event_rows].where(event_id: ids)
        entries = rows.where(tbl: "inbox_entries").select(:row_id)
        db[:inbox_entries].where(id: entries).delete
        rows.delete
        db[:events].where(id: ids).delete
        renumber(db, ledger)
    end

    # The N counter back at the newest entry left.
    def self.renumber(db, ledger)
        last = db[:inbox_entries].where(ledger_id: ledger).max(:n) || 0
        db[:counters].where(ledger_id: ledger, kind: "N").update(last:)
    end

    def self.main(argv)
        word, address, mark = argv
        journal = Ledger::Journal.open
        case word
        when "mark" then puts mark(journal, address)
        when "rewind" then rewind(journal, address, mark.to_s)
        else abort "usage: fixture_rewind.rb mark|rewind ADDRESS [E<n>]"
        end
    ensure
        journal&.close
    end
end

FixtureRewind.main(ARGV) if $PROGRAM_NAME == __FILE__
