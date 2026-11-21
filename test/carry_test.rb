# frozen_string_literal: true

require "test_helper"

# rake user:carry: the users of the JSON store sesam kept before the
# journal, carried into the journal once.
class CarryTest < Minitest::Test
    def setup
        @dir = Dir.mktmpdir("carry", SANDBOX)
        @journal = Fixture.journal(@dir)
        @store = LedgerViewer::Accounts.open(@journal)
        @json = File.join(@dir, "users.json")
    end

    def teardown = @journal.close

    def old_user(name)
        LedgerViewer::Accounts.invite(Sesam::JsonStore.new(@json), name)
    end

    def test_every_user_and_invitation_is_carried
        old_user("alice")
        old_user("bob")
        counts = LedgerViewer::Accounts.carry(@json, @store).to_h

        assert_equal 2, counts[:users]
        assert_equal 2, counts[:invites]
        assert_equal %w[alice bob],
                     Sesam::Users.new(@store).list.map(&:name).sort
    end

    def test_a_journal_holding_users_is_refused
        old_user("alice")
        LedgerViewer::Accounts.carry(@json, @store)

        assert_raises(LedgerViewer::Error) do
            LedgerViewer::Accounts.carry(@json, @store)
        end
    end

    def test_a_missing_file_is_refused
        assert_raises(LedgerViewer::Error) do
            LedgerViewer::Accounts.carry(File.join(@dir, "none.json"), @store)
        end
    end
end
