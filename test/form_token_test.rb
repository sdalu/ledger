# frozen_string_literal: true

require "test_helper"

# The token a ledger page's forms carry belongs to one session.
class FormTokenTest < Minitest::Test
    Held = Struct.new(:name, :issued)
    SECRET = "s" * 40

    def token(held, secret = SECRET) = LedgerViewer::FormToken.for(secret, held)

    def test_one_session_has_one_token
        assert_equal token(Held.new("alice", 5)), token(Held.new("alice", 5))
        assert_match(/\A\h{64}\z/, token(Held.new("alice", 5)))
    end

    def test_another_user_another_session_or_another_secret_has_another
        base = token(Held.new("alice", 5))

        refute_equal base, token(Held.new("bob", 5))
        refute_equal base, token(Held.new("alice", 6))
        refute_equal base, token(Held.new("alice", 5), "t" * 40)
    end

    def test_a_caller_with_no_session_gets_a_token_of_its_own
        refute_equal token(nil), token(Held.new("alice", 5))
    end
end
