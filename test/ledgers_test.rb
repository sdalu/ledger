# frozen_string_literal: true

require "test_helper"

# What the pages lean on from the journal: the live ledgers in its
# order, the id in a URL, the version a stamp moves with, and the
# document a page reads.
class LedgersTest < Minitest::Test
    def setup
        @dir = Dir.mktmpdir("ledgers", SANDBOX)
        @journal = Fixture.journal(@dir)
        @ledgers = LedgerViewer::Ledgers.new(@journal)
    end

    def teardown = @journal.close

    def address(name) = File.join(@dir, name, "LEDGER.md")

    def test_the_live_ledgers_in_the_journals_order
        %w[b a].each { Fixture.ledger(@journal, address(it), project: it) }

        assert_equal [address("b"), address("a")], @ledgers.all.map(&:path)
    end

    def test_the_id_is_the_hash_of_the_address
        Fixture.ledger(@journal, address("a"), project: "a")

        assert_equal Digest::SHA1.hexdigest(address("a"))[0, 10],
                     @ledgers.all.first.id
    end

    def test_an_event_moves_the_version
        Fixture.ledger(@journal, address("a"), project: "a")
        before = @ledgers.all.first.version
        Ledger::Write.run(@journal, address("a"), "touch", []) { nil }

        refute_equal before, @ledgers.all.first.version
    end

    def test_the_document_is_json_v1_with_string_keys
        Fixture.ledger(@journal, address("a"), project: "a")
        document = @ledgers.read(@ledgers.all.first)

        assert_equal 1, document["schema"]
        assert_equal "ledger", document["kind"]
        assert_equal address("a"), document["ledger"]["address"]
    end
end
