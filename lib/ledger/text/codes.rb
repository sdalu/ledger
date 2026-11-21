# frozen_string_literal: true

module Ledger
    module Text
        # Codes in ledger text: a token of one or two capitals and digits
        # (W1, S4, H12) standing alone, whose letter is not one of a
        # ledger's kinds, says nothing to a reader who has not seen where
        # it comes from. Pure: strings in, tokens out.
        #
        #     Ledger::Text::Codes.find("follow W1 on P3")   # => ["W1"]
        #     Ledger::Text::Codes.find('"W1" and `S4`')     # => []
        module Codes
            # The letters of a ledger's ids, those the commands take too.
            KINDS = %w[P O D C F X N Z E L G A].freeze
            # Not after a word character, / . _ or -; not followed by a
            # word character, a / or a .ext: then it is a path or a name.
            CODE = %r{(?<![\p{Word}/.-])[A-Z]{1,2}[0-9]+
                      (?![\p{Word}/]|[.-]\p{Word})}x
            # Set aside before looking: code spans, the user's words in
            # double quotes, and URLs.
            ASIDE = [/`[^`]*`/, /"[^"\n]*"/, /“[^”\n]*”/,
                     %r{\S+://\S*}].freeze

            module_function

            # The codes of TEXT that are not a kind's ids, each once.
            def find(text)
                bare = ASIDE.reduce(text.to_s) { |out, rx| out.gsub(rx, " ") }
                bare.scan(CODE).reject { kind?(it) }.uniq
            end

            # A one-letter code of a kind; two capitals are never a kind.
            def kind?(token) = KINDS.include?(token[/\A[A-Z]+/])

            # Whether TEXT names TOKEN whole, anywhere (quotes included).
            def names?(text, token)
                /(?<!\p{Word})#{token}(?![0-9])/.match?(text.to_s)
            end
        end
    end
end
