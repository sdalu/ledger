# frozen_string_literal: true

module LedgerViewer
    # The same word for several pieces, in one request: each must still
    # await exactly those words and have none sent unfiled, else nothing
    # is sent; one ordinary word entry per piece.
    module SayAll
        def all
            refs = Render::Text.words(@form["refs"])
            given = words(@form["word"])
            named!(refs, given)
            stale!(refs, given)
            held!(refs)
            bodies = refs.map { body(it, given) }
            [bodies.first.with(anchor: "p-#{refs[0]}"), *bodies.drop(1)]
        end

        private

        def named!(refs, given)
            return if refs.length >= 2 && refs.uniq == refs &&
                      !given.empty? && !given.include?("other")

            refuse(400, "Name two or more pieces once each, and the " \
                        "words to give them.")
        end

        def stale!(refs, given)
            by_id = pieces.to_h { [it["id"], it] }
            stale = refs.reject do |ref|
                by_id[ref] && words_of(by_id[ref]).sort == given.sort
            end
            return if stale.empty?

            refuse(409, "#{stale.join(", ")} no longer await exactly " \
                        "#{given.join(", ")}: reload the page. " \
                        "Nothing was sent.")
        end

        def held!(refs)
            held = refs.select { sent(it, word: true).any? }
            return if held.empty?

            refuse(409, "#{held.join(", ")} already have a word the " \
                        "session has not filed: reload the page. " \
                        "Nothing was sent.")
        end

        def body(ref, given)
            Say::Body.new(fields: { "ref" => ref, "word" => given.join(", ") },
                          text: "", anchor: nil)
        end
    end
end
