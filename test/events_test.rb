# frozen_string_literal: true

require "socket"

require "test_helper"
require_relative "support/ledger_fixture"

# The live updates: the stamp a page polls, and the stream that pushes
# it when it moves.
class EventsTest < ViewerTest
    include LedgerFixture

    def test_the_stamp_is_the_pages
        sign_in
        https "/l/#{@lid}"
        page = last_response.body[/data-stamp="(\h+)"/, 1]
        https "/stamp"
        headers = last_response.headers

        assert_equal page, last_response.body
        assert_equal "no-store", headers["Cache-Control"]
        assert_includes headers["Content-Type"], "text/plain"
    end

    def test_the_stamp_and_the_stream_are_behind_the_gate
        ["/stamp", "/events"].each do |path|
            https path

            assert_equal 401, last_response.status, path
        end
    end

    def test_the_stream_opens_and_sends_a_stamp_that_is_not_the_pages
        sign_in
        status, headers, body = stream("/events?since=old")
        chunks = take(body, 2)

        assert_equal 200, status
        assert_equal "text/event-stream", headers["Content-Type"]
        assert_equal "no-store", headers["Cache-Control"]
        assert_equal ": open\n\n", chunks[0]
        assert_match(/\Aevent: stamp\ndata: \h{16}\n\n\z/, chunks[1])
    end

    def test_a_stream_of_the_current_stamp_says_nothing_until_it_moves
        sign_in
        https "/stamp"
        now = last_response.body
        _, _, body = stream("/events?since=#{now}")
        chunks = take(body, 2) { File.write("#{@ledger}.inbox", "{}\n") }

        assert_equal ": open\n\n", chunks[0]
        assert_match(/\Aevent: stamp\ndata: (?!#{now})\h{16}\n\n\z/, chunks[1])
    end

    def test_an_idle_stream_sends_a_comment_every_fifteen_ticks
        stamp = -> { "s" }
        chunks = []
        LedgerViewer::Events.new("s", stamp, pause: 0).each do |chunk|
            chunks << chunk
            break if chunks.length == 3
        end

        assert_equal [": open\n\n", ":\n\n", ":\n\n"], chunks
    end

    def test_a_stream_ends_when_its_client_goes
        client, server = UNIXSocket.pair
        events = LedgerViewer::Events.new("s", -> { "s" }, pause: 0.05,
                                                           socket: server)
        thread = Thread.new { events.each { |_| nil } }
        client.close

        assert thread.join(2), "the stream outlived its client"
    end

    private

    def stream(path)
        jar = rack_mock_session.cookie_jar.to_hash
        cookie = jar.map { |name, value| "#{name}=#{value}" }.join("; ")
        env = Rack::MockRequest.env_for(
            path, Fixture::HOST.merge("HTTP_COOKIE" => cookie,
                                      "HTTP_ACCEPT" => "text/event-stream")
        )
        app.call(env)
    end

    # The first `count` chunks, `after_first` run once the first is in.
    def take(body, count, &after_first)
        chunks = []
        body.each do |chunk|
            chunks << chunk
            after_first&.call if chunks.length == 1
            break if chunks.length == count
        end
        chunks
    end
end
