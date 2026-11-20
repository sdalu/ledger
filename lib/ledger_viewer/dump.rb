# frozen_string_literal: true

require "json"

module LedgerViewer
    # A ledger as the Python viewer reads it, from the engine's own
    # ledger-dump.py: the Hash its read() builds (string keys), or nil
    # when the ledger cannot be read, the engine does not answer in time
    # or says something that is not JSON.
    class Dump
        SCRIPT = "ledger-dump.py"

        def initialize(python:, script:, timeout:)
            @command = [python, File.join(File.dirname(script), SCRIPT)]
            @timeout = timeout
        end

        def read(path)
            out, _err, finished = Engine.run([*@command, path], @timeout)
            return unless finished

            data = JSON.parse(out)
            data if data.is_a?(Hash)
        rescue JSON::ParserError, SystemCallError
            nil
        end
    end
end
