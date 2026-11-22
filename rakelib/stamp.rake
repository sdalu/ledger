# frozen_string_literal: true

require "ledger/gate_stamp"

# stamp.rake -- the stamp of the default task (docs/journal.md, the gate
# stamp): the tree of the git index is taken before the run and stamped
# after it, when it passed and the index is still that tree. The
# pre-commit hook (ledger githook) reads the stamps.

namespace :stamp do
    tested = nil

    desc "Take the index tree the gate is about to test"
    task :begin do
        tested = Ledger::GateStamp.tree(Dir.pwd)
    end

    desc "Stamp the tree taken by stamp:begin, when the index still holds it"
    task :write do
        if Ledger::GateStamp.write(Dir.pwd, tested)
            puts "gate stamp written for tree #{tested}"
        else
            warn "gate stamp: the index changed during the run; " \
                 "nothing stamped"
        end
    end
end
