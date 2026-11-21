# frozen_string_literal: true

module Ledger
    module Text
        # What a title is, and the split of a "title: detail" text.
        # Pure: strings in, a refusal message or nil out.
        module Title
            MAX     = 60
            TOKEN   = /[\p{Word}'’-]+/
            ID_WORD = /\A[A-Z]{1,3}[0-9]+[a-z]?\z/
            FIELD   = " — "

            MOSTLY_IDS = "the title is mostly ids; name the subject in " \
                         "words (`Calendar priority range`, not `O13 D1`)"

            module_function

            # "Short title: the detail — field: …" -> ["Short title",
            # "the rest"]; a text with no ": " before its first field is
            # all title.
            def split(text)
                first = text.split(FIELD, -1).first.to_s
                head, sep, = first.partition(": ")
                return [first.strip, strip_dash(text[first.length..])] \
                    if sep.empty? || head.strip.empty?

                [head.strip, text[(head.length + 2)..].strip]
            end

            # Why TITLE does not read as a title, or nil: it has to stand
            # alone where the viewer shows it without the detail, so it is
            # a short phrase in words, not a list of ids.
            def problem(title)
                text = title.strip
                return "the title is empty" if text.empty?

                shape(text) || (MOSTLY_IDS if ids?(text))
            end

            # Why DETAIL reads as a list of ids rather than words, or nil:
            # ids outnumbering words two to one say nothing to a reader who
            # has not seen the ids. A trailing "— field: …" is not part of
            # the detail.
            def detail_problem(detail)
                text = detail.split(FIELD, -1).first.to_s.strip
                return nil if text.empty?

                ids, words = count(text)
                return nil unless ids * 2 > words

                "the detail is mostly ids; say in words what they stand " \
                    "for, or point to them with — see:"
            end

            def shape(text)
                if text.length > MAX
                    "the title is #{text.length} characters, at most #{MAX}"
                elsif text.include?(": ")
                    "the title holds `: `, which starts the detail"
                elsif text.end_with?("…", "...")
                    "the title is cut short; say it in fewer words"
                end
            end

            def strip_dash(text) = text.sub(/\A[ —]+/, "")

            def ids?(text)
                ids, words = count(text)
                words < 2 || ids > words
            end

            # -> [ids, words] among the tokens of TEXT: a word has at least
            # three letters.
            def count(text)
                tokens = text.scan(TOKEN)
                ids, rest = tokens.partition { ID_WORD.match?(it) }
                [ids.size, rest.count { it.scan(/\p{Alpha}/).size >= 3 }]
            end
        end
    end
end
