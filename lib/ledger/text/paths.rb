# frozen_string_literal: true

module Ledger
    module Text
        # The paths a text names, as a brief or a constraint names them:
        # a token starting with `~/`, `./`, `../` or `/`; one with a
        # slash and a file extension; one ending in a slash (a
        # directory); or a bare name with a known extension. `and/or` is
        # none of them.
        #
        #     Ledger::Text::Paths.scan("see lib/x.rb:12 and docs/")
        #     # => ["lib/x.rb", "docs/"]
        #     Ledger::Text::Paths.covered?("docs/", ["docs/a.md"]) # => true
        module Paths
            # \w as Unicode.
            PATH = %r{(?<![[:word:]/])
                      ((?:~/|\.{1,2}/|/)[[:word:].-]+(?:/[[:word:].-]*)*
                      |(?:[[:word:].-]+/)+[[:word:].-]+\.[[:alpha:]][[:word:]]*
                      |[[:word:]-]+\.(?:py|c|h|rb|md|json|ya?ml|toml|js|ts|
                                       go|rs|sh|bib|tex|csv|txt)
                      |(?:[[:word:].-]+/)+)
                      (?![[:word:]]|\.[[:word:]])}x

            module_function

            def scan(text)
                text.to_s.scan(PATH).flatten.map { it.sub(/[.,;:]+\z/, "") }
            end

            # Whether PATH is one of the NAMED path tokens, or a directory
            # (trailing slash) one of them lies under.
            def covered?(path, named)
                named.any? do |token|
                    token == path ||
                        (path.end_with?("/") && token.start_with?(path))
                end
            end
        end
    end
end
