# frozen_string_literal: true

require "ledger/gate_stamp"

module Ledger
    module Commands
        # `gate-stamp [PATH] [--tree TREE]`: the call a gate makes at its
        # end, once it has passed.
        class GateStamp < CLI::Command
            USAGE = "[PATH]"
            SUMMARY = "record that the gate passed for the tree of PATH's " \
                      "git index (the current directory by default), for " \
                      "the pre-commit hook (githook). TREE is the tree the " \
                      "gate took before it ran (`git write-tree`); when " \
                      "the index has changed since, nothing is written"
            OPTIONS = { tree: ["--tree TREE", "the tree tested, taken " \
                                              "before the run"] }.freeze

            private

            def run(path = Dir.pwd)
                tested = @opts[:tree] || Ledger::GateStamp.tree(path)
                if Ledger::GateStamp.write(path, tested)
                    @out.puts "stamped #{tested}"
                else
                    @err.puts "gate-stamp: the index is not the tree " \
                              "tested; nothing stamped"
                end
                0
            end
        end
    end
end
