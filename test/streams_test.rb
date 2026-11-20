# frozen_string_literal: true

require "test_helper"
require "net/http"
require "puma"
require "socket"
require_relative "support/ledger_fixture"

# Every open page holds an event stream, and a stream holds a request
# thread: with the configured threads, five of them leave room for a
# page request; with four threads they do not (the control).
class StreamsTest < ViewerTest
    include LedgerFixture

    STREAMS = 5

    def test_open_streams_do_not_block_a_page_request
        assert_equal :ok, health_beside_streams(LedgerViewer::THREADS)
    end

    def test_the_control_four_threads_are_starved
        assert_equal :blocked, health_beside_streams(4)
    end

    private

    # :ok when /health answers while STREAMS streams are open on a
    # server with `threads` request threads, else :blocked.
    def health_beside_streams(threads)
        sign_in
        server = serve(threads)
        port = server.connected_ports.first
        sockets = Array.new(STREAMS) { open_stream(port) }
        health(port)
    ensure
        sockets&.each(&:close)
        server&.halt
    end

    def serve(threads)
        server = Puma::Server.new(app, nil, min_threads: 0,
                                            max_threads: threads)
        server.add_tcp_listener("127.0.0.1", 0)
        server.run
        server
    end

    def open_stream(port)
        socket = TCPSocket.new("127.0.0.1", port)
        socket.write("GET /events HTTP/1.1\r\nHost: localhost\r\n" \
                     "Accept: text/event-stream\r\nCookie: #{cookie}\r\n\r\n")
        socket
    end

    def cookie
        rack_mock_session.cookie_jar.to_hash
                         .map { |name, value| "#{name}=#{value}" }.join("; ")
    end

    def health(port)
        http = Net::HTTP.new("127.0.0.1", port)
        http.read_timeout = 2
        http.get("/health", "Host" => "localhost").body == "ok\n" ? :ok : :bad
    rescue Net::ReadTimeout, Net::OpenTimeout
        :blocked
    end
end
