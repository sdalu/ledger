# frozen_string_literal: true

module LedgerViewer
    # The user's words on the ledger itself: its Close and its Abandon,
    # each sent with no text as well.
    module SayLedger
        WORDS = %i[close abandon].freeze

        private

        def ledger_word?(kind) = WORDS.include?(kind)

        def ledger_word(kind) = kind == :close ? close : abandon

        # The ledger closed on the user's word: offered only when the
        # status line proposes it, which it stops doing once any entry,
        # a Close sent before among them, waits to be filed.
        def close
            return if @reading.ready_to_close?

            refuse(409, "This ledger is not ready to close: its status " \
                        "no longer proposes it; reload the page.")
        end

        # The ledger abandoned on the user's word: offered on any live
        # ledger, once; a second waits for the first to be filed.
        def abandon
            return if @reading.unfiled_on("abandon").empty?

            refuse(409, "Abandoning this ledger is already asked and not " \
                        "filed yet.")
        end
    end
end
