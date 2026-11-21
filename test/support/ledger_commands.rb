# frozen_string_literal: true

require "delegate"
require "stringio"

require "ledger"
require "ledger/cli"

# bin/ledger's words, run on a journal the caller holds open: how every
# fixture builds its ledgers. A command closes its journal when done,
# so it is handed one it cannot close; inside the caller's transaction
# its writes are the caller's, all or none.
module LedgerCommands
    # The caller's journal, lent to one command.
    class Lent < SimpleDelegator
        def close = nil
    end

    # What `ledger WORD ARGV...` printed; a refusal raises, as does any
    # exit status but 0.
    def self.run(journal, word, *argv)
        out = StringIO.new
        err = StringIO.new
        command = Ledger::Commands.const_get(word.capitalize)
                                  .new(argv, out:, err:)
        command.instance_variable_set(:@journal, Lent.new(journal))
        code = command.call
        return out.string if code.zero?

        raise Ledger::Refused, "ledger #{word} answered #{code}: #{err.string}"
    end
end
