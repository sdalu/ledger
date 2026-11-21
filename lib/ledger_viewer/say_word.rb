# frozen_string_literal: true

module LedgerViewer
    # The user's word on a piece, and the replaced words and answers.
    module SayWord
        LIST = /[,[:space:]\x1c-\x1f]+/

        private

        # The word a piece awaits, several of them, or drop.
        def word(ref, fields)
            found = piece(ref)
            names = words_of(found)
            given = words(@form["word"])
            check_given(ref, found, names, given)
            replaces!(fields, ref, :word)
            fields["word"] = given.join(", ")
        end

        def check_given(ref, piece, names, given)
            if given == ["drop"]
                return unless piece.nil? || piece["status"] == "dropped"

                refuse(409, "#{ref} is no piece to drop; send a note if " \
                            "it must go.")
            elsif names.empty?
                refuse(409, "#{ref} awaits no word now; send a note if " \
                            "it is needed.")
            elsif given.empty? || !(given - names).empty?
                refuse(400, "#{ref} awaits #{names.join(", ")}.")
            end
        end

        def words(text)
            text.split(",").map { Render::Text.strip(it) }.reject(&:empty?)
        end

        # The entries of this ledger's inbox no session has taken, but
        # the comments on a question and the pictures asked: they answer
        # nothing to replace.
        def pending
            @reading.inbox.reject { it["taken"] || Render::Terms.aside?(it) }
        end

        def sent(ref, word: false)
            pending.select { it["ref"] == ref && (!word || word?(it)) }
                   .map { it["id"] }
        end

        def word?(entry) = !(entry["word"].nil? || entry["word"].empty?)

        def replaces!(fields, ref, what)
            filed = sent(ref, word: what == :word)
            said = @form["replaces"].split(LIST).reject(&:empty?)
            refuse(409, replaced_why(ref, filed, what)) unless
                said.sort == filed.sort
            fields["replaces"] = filed unless filed.empty?
        end

        def replaced_why(ref, sent, what)
            if sent.empty?
                return "#{ref}: the #{what} it replaced was filed; " \
                       "reload the page."
            end

            "#{ref} already has #{what == :word ? "a word" : "an answer"} " \
                "the session has not filed (#{sent.join(", ")}): " \
                "change it from its card, after a reload."
        end
    end
end
