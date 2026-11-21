# frozen_string_literal: true

require_relative "render/json_test"

# Reading a ledger of the journal, and refusing a document of another
# schema.
class ReadTest < JsonCase
    def test_a_ledger_is_read_by_address_or_by_id
        build

        assert_equal document, Ledger::Read.ledger(@journal, @ledger[:id],
                                                   now: NOW)
    end

    def test_a_closed_ledger_is_read_by_id
        build
        db[:ledgers].where(id: @ledger[:id]).update(closed_at: T0 + 9)

        assert_equal "2023-11-14T23:13:20+01:00",
                     Ledger::Read.ledger(@journal, @ledger[:id],
                                         now: NOW)[:ledger][:closed_at]
        assert_raises(Ledger::Unknown) { document }
    end

    def test_an_unknown_ledger_is_refused
        assert_raises(Ledger::Unknown) do
            Ledger::Read.ledger(@journal, "/work/nowhere/LEDGER.md")
        end
        assert_raises(Ledger::Unknown) { Ledger::Read.ledger(@journal, 99) }
    end

    def test_a_document_read_back_from_its_text_is_the_same_document
        build
        text = Ledger::Render::Json.generate(document)

        assert_equal JSON.parse(text), Ledger::Read.parse(text)
    end

    def test_a_schema_the_reader_does_not_know_is_refused
        ['{"schema":2,"kind":"ledger"}', '{"kind":"ledger"}', "[]",
         '{"schema":"1"}'].each do |text|
            assert_raises(Ledger::Refused) { Ledger::Read.parse(text) }
        end
    end

    def test_the_refusal_names_both_schemas
        error = assert_raises(Ledger::Refused) do
            Ledger::Read.accept("schema" => 7)
        end

        assert_equal "JSON schema 7: this reader knows 1", error.message
    end

    def test_a_claim_released_and_taken_again_dates_from_the_second_take
        build
        write("release", [], at: T0 + (3 * MINUTE)) do |change|
            change.update(:pieces, 3, status: "planned", claimed_by: nil)
        end
        assert_nil claim_of

        write("out", [], at: T0 + (4 * MINUTE)) { claim(it, "s2") }

        assert_equal({ session: "s2", since: "2023-11-14T23:17:20+01:00" },
                     claim_of)
    end

    def claim_of = document[:pieces][2][:claim]
end

# The index of every ledger of the journal.
class LedgerIndexTest < JsonCase
    GAMMA = "/work/gamma/LEDGER.md"
    BETA = "/work/beta/LEDGER.md"
    ALPHA_STATUS = "Status (Ledger in Ruby) — criteria 1/1 · " \
                   "pieces 1/3 verified · out: P3 · " \
                   "stalled: P3 · being prepared: O1 (P3) · your word: " \
                   "P2 (commit)"

    def setup
        super
        build
        other(GAMMA, "gamma", at: T0) { gamma(it) }
        other(BETA, "beta", at: T0 + (10 * MINUTE)) { goal(it) }
        db[:ledgers].where(place: "/work/beta").update(closed_at: T0 + 9)
        db[:ledgers].update(created_at: T0)
    end

    def other(address, project, at:, &)
        @journal.create_ledger(address, project:)
        Ledger::Write.run(@journal, address, "import", [], at:, &)
        project
    end

    def gamma(change)
        goal(change, title: "Gamma", short: "second")
        question(change)
        change.insert(:inbox_entries, n: change.next_id("N"),
                                      at: "2026-11-20 10:00:00", payload: "{}")
    end

    def entry(who, what, times, rest)
        id, address, project = who
        title, short = what
        { id:, address:, project:, title:, short:,
          created_at: "2023-11-14T23:13:20+01:00", **times, **rest }
    end

    def test_the_index_is_one_whole_document_live_ledgers_first
        assert_equal({ schema: 1, kind: "index",
                       ledgers: [alpha, gamma_entry, beta_entry] },
                     Ledger::Read.index(@journal, now: NOW))
    end

    def alpha
        entry([1, ADDRESS, "alpha"], ["Ledger in Ruby", "one journal"],
              { updated_at: "2023-11-14T23:15:20+01:00", closed_at: nil },
              status: ALPHA_STATUS, waiting: [], words: %w[P2], pending: [])
    end

    def gamma_entry
        entry([2, GAMMA, "gamma"], %w[Gamma second],
              { updated_at: "2023-11-14T23:13:20+01:00", closed_at: nil },
              status: "Status (Gamma) — criteria 0/0 · " \
                      "pieces 0/0 verified · " \
                      "waiting on you: O1 · from the viewer: N1",
              waiting: %w[O1], words: [], pending: %w[N1])
    end

    def beta_entry
        entry([3, BETA, "beta"], [nil, nil],
              { updated_at: "2023-11-14T23:23:20+01:00",
                closed_at: "2023-11-14T23:13:20+01:00" },
              status: "Status (/work/beta/LEDGER.md) — criteria 0/0 · " \
                      "pieces 0/0 verified",
              waiting: [], words: [], pending: [])
    end

    def test_the_index_keys_are_in_the_agreed_order
        keys = Ledger::Read.index(@journal, now: NOW)[:ledgers].first.keys

        assert_equal %i[id address project title short created_at updated_at
                        closed_at status waiting words pending], keys
    end

    def test_a_journal_without_ledgers_has_an_empty_index
        empty = Ledger::Render::Json.index([])

        assert_equal({ schema: 1, kind: "index", ledgers: [] }, empty)
    end
end
