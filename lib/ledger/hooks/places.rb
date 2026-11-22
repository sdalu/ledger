# frozen_string_literal: true

module Ledger
    module Hooks
        # The places a hook payload's ledgers live at: its cwd (the
        # current directory when it names none), cwd/.claude and its
        # scratchpad_dir, in that order. Standard library alone: the
        # fast-path hooks read it too.
        module Places
            module_function

            def of(payload)
                cwd = payload["cwd"].to_s
                cwd = Dir.pwd if cwd.empty?
                [cwd, File.join(cwd, ".claude"), payload["scratchpad_dir"].to_s]
                    .reject(&:empty?).uniq
            end
        end
    end
end
