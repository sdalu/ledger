# frozen_string_literal: true

module LedgerViewer
    # The live updates, as a Rack body: server-sent events.
    # "event: stamp" when the stamp moves, a
    # comment line every 15 quiet seconds, and it ends when the client
    # goes (the write that cannot be made raises in the server).
    # `since` is the page's own stamp, so a change between the page's
    # render and this connection is sent at once. `socket`, when given,
    # is the client's: a readable socket with nothing to read is a client
    # that left, which ends the stream at once rather than at the next
    # write, so that its thread is free for the next page.
    class Events
        QUIET = 15

        # `stamp` answers the current stamp when called.
        def initialize(since, stamp, pause: 1.0, socket: nil)
            @since = since
            @stamp = stamp
            @pause = pause
            @socket = socket
        end

        def each
            yield ": open\n\n"
            quiet = 0
            loop do
                current = @stamp.call
                quiet = tick(current, quiet) { yield it }
                break unless alive?
            end
        end

        # One pause, cut short when the client writes or goes; whether
        # the client is still there.
        def alive?
            return sleep(@pause).positive? || true unless @socket
            return true unless @socket.to_io.wait_readable(@pause)

            present?
        end

        # Whether the client is still there: what is readable is its
        # bytes, not its end.
        def present?
            !@socket.read_nonblock(4096).empty?
        rescue IO::WaitReadable
            true
        rescue EOFError, SystemCallError
            false
        end

        # How many quiet ticks now, having written what is due.
        def tick(current, quiet)
            if current != @since
                @since = current
                yield "event: stamp\ndata: #{current}\n\n"
                1
            elsif quiet >= QUIET
                yield ":\n\n"
                1
            else
                quiet + 1
            end
        end
    end
end
