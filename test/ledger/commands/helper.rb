# frozen_string_literal: true

require "stringio"

require_relative "../helper"
require "ledger/cli"

# A journal test that runs commands as bin/ledger does, through
# Ledger::CLI.run, on a ledger BETA made by `new`; a refusal is asserted
# to give its exit status, its words and to leave the journal as it was.
class CommandCase < JournalTest
    BETA = "/work/beta/LEDGER.md"
    GOAL = ["--goal", "build the thing now", "--title", "Build the thing",
            "--short", "build it", "--date", "2026-11-20"].freeze

    def setup
        super
        ok("new", BETA, *GOAL)
        @beta = db[:ledgers].where(place: "/work/beta").get(:id)
    end

    # -> [exit status, stdout, stderr] of one command.
    def cli(*argv)
        out = StringIO.new
        err = StringIO.new
        code = Ledger::CLI.run(argv, out:, err:)
        [code, out.string, err.string]
    end

    # The command's stdout, its status asserted 0.
    def ok(*argv)
        code, out, err = cli(*argv)
        assert_equal 0, code, "#{argv.join(" ")}: #{err}"
        out
    end

    # Everything a refused command must leave alone.
    def state
        [db[:ledgers].count, db[:events].count, db[:event_rows].count,
         db[:counters].select_map(%i[ledger_id kind last]),
         Ledger::Snapshot.read(db, @beta)]
    end

    def assert_refused(*argv, message, code: 2)
        before = state
        status, _out, err = cli(*argv)
        assert_equal code, status, err
        assert_includes err, message
        assert_equal before, state, "a refusal wrote"
    end

    def snapshot = Ledger::Snapshot.read(db, @beta)

    def markdown = Ledger::Render::Markdown.render(snapshot)

    # A planned piece of BETA serving criterion D<n>.
    def piece_serving(n)
        Ledger::Write.run(@journal, BETA, "piece", []) do |change|
            id = piece(change)
            criterion = db[:criteria].where(ledger_id: @beta, n:).get(:id)
            change.insert(:piece_links, piece_id: id, kind: "for", position: 0,
                                        criterion_id: criterion)
        end
    end
end
