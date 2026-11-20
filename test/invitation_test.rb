# frozen_string_literal: true

require "test_helper"

class InvitationTest < ViewerTest
    def test_the_sign_in_and_invitation_pages_are_open
        %w[/sign-in /invite].each do |path|
            https path

            assert_predicate last_response, :ok?, path
        end
    end

    def test_an_invitation_is_spent_once_and_refused_the_second_time
        token = LedgerViewer::Accounts.invite(@db, "alice")
        post_json("/session/invite", token:, password: Fixture::PASSWORD)

        assert_predicate last_response, :ok?
        post_json("/session/invite", token:, password: "another long password")

        refute_predicate last_response, :ok?
    end

    def test_signing_in_with_the_password_gives_a_session
        sign_in
        https "/session"

        assert_predicate last_response, :ok?
    end

    def test_a_wrong_password_gives_no_session
        sign_in
        clear_cookies
        post_json("/session/password", name: "alice", password: "wrong one")

        refute_predicate last_response, :ok?
        https "/"

        assert_equal 401, last_response.status
    end

    def test_a_lan_caller_is_not_admitted_without_signing_in
        https "/", :get, nil, "REMOTE_ADDR" => "192.0.2.9"

        assert_equal 401, last_response.status
    end
end
