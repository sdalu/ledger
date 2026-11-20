# frozen_string_literal: true

require "test_helper"

class HealthTest < ViewerTest
    def test_health_answers_without_signing_in
        https "/health"

        assert_predicate last_response, :ok?
        assert_equal "ok\n", last_response.body
    end

    def test_health_answers_on_a_permitted_host_name
        get "/health", {}, Fixture::HOST.merge("HTTP_HOST" => "localhost:4599")

        assert_predicate last_response, :ok?
    end

    def test_a_host_not_in_the_bind_list_is_refused
        get "/health", {}, Fixture::HOST.merge("HTTP_HOST" => "evil.example")

        assert_equal 403, last_response.status
    end
end
