# frozen_string_literal: true

require_relative "render/picture_fold"

module LedgerViewer
    # A picture asked of the session on a card that has none: the kind
    # wanted and what it should show. It answers nothing and gives no
    # word, so it replaces nothing and nothing has to replace it.
    module SayPicture
        # The kinds the card's fold offers.
        PICTURES = Render::PictureFold::KINDS.keys.freeze

        private

        def picture?(ref) = !@form["picture"].empty? && ref.match?(/\A[OP]/)

        def picture(ref, fields)
            refuse(400, "Say what the picture should show.") if @text.empty?
            kind = @form["picture"]
            unless PICTURES.include?(kind)
                refuse(400, "A picture is one of #{PICTURES.join(", ")}, " \
                            "not #{py_repr(kind)}.")
            end
            card!(ref)
            fields["picture"] = kind
        end

        # The question still open, or the piece still drawn as a card:
        # unfinished, or awaiting the user's word.
        def card!(ref)
            shown = if ref.start_with?("O") then @data["questions"]
                    else @reading.flight + @reading.owed
                    end
            return if shown.any? { it["id"] == ref }

            refuse(409, "#{ref} is no longer a card on this page; send it " \
                        "as a note.")
        end
    end
end
