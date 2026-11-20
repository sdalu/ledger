# frozen_string_literal: true

require "open3"

module LedgerViewer
    # The engine's subprocess, run once the same way wherever it is asked:
    # with a timeout, the run killed with its group when it overstays.
    module Engine
        # [stdout, stderr, whether it finished in time].
        def self.run(command, timeout)
            Open3.popen3(*command, pgroup: true) do |stdin, *pipes, wait|
                stdin.close
                readers = pipes.map { |io| Thread.new { io.read } }
                finished = wait.join(timeout)
                kill(wait.pid) unless finished
                [*readers.map(&:value), finished]
            end
        end

        def self.kill(pid)
            Process.kill("KILL", -pid)
        rescue SystemCallError
            nil
        end
    end
end
