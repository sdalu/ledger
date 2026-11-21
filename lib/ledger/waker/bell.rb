# frozen_string_literal: true

require "socket"

module Ledger
    module Waker
        # The doorbell on a session's messaging socket: one line, written
        # whole, then the connection closed. No auth line: the probe
        # showed the socket takes a line from the same user without one,
        # and the token is never read.
        module Bell
            TIMEOUT = 5

            module_function

            # -> nil when the line was written, else why it was not.
            def ring(path, line)
                return "no socket recorded" if path.to_s.empty?

                socket = Socket.unix(path)
                write(socket, line)
                nil
            rescue SystemCallError, IOError => e
                e.message
            ensure
                socket&.close
            end

            def write(socket, line)
                rest = line.b
                until rest.empty?
                    raise IOError, "timed out writing" unless
                        socket.wait_writable(TIMEOUT)

                    rest = rest.byteslice(socket.write_nonblock(rest)..)
                end
                socket.close_write
            end
        end
    end
end
