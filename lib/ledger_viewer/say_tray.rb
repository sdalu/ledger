# frozen_string_literal: true

module LedgerViewer
    # What a tray holds: a word on a piece, a comment on a piece or on a
    # question, a drop of either. Answers, notes, the ledger's Close and
    # Abandon, pictures asked and the order are sent on their own.
    module SayTray
        # The one entry an item of the tray makes, by the rules of its
        # single send, or the Refusal that names why it is not one.
        def trayed
            ref = @form["ref"]
            unless trayable?(kind_of(ref.empty? ? nil : ref))
                refuse(400, "#{ref.empty? ? "A note" : ref} is sent on its " \
                            "own, not from the tray.")
            end
            one
        end

        private

        def trayable?(kind)
            case kind
            when :word, :comment then true
            when :answer then asked_or_dropped?
            else false
            end
        end

        def asked_or_dropped?
            !@form["comment"].empty? || @form["word"] == "drop"
        end
    end
end
