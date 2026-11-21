# frozen_string_literal: true

require_relative "terms"

module LedgerViewer
    module Render
        # A ledger's pictures by name: what kind of picture a name is,
        # and which names are one before/after pair.
        module Folder
            ITEM_CODE = /\A[a-z]+\d+-/i
            BEFORE = "before-"

            module_function

            def kind(name)
                low = name.downcase
                if Terms::MOCKUP_IMAGES.any? { low.end_with?(it) } then "image"
                elsif low.end_with?(".txt") then "text"
                else "page"
                end
            end

            # {after name => before name}: `before-X.ext` pairs with the
            # image or page of the directory whose name, minus one
            # leading item code and the extension, is X. `real` maps each
            # name to its one file, or nil for a directory.
            def pairs(names, real)
                stems = stems_of(names, real)
                names.each_with_object({}) do |name, found|
                    key = key_of(name, real, after: false) or next
                    after = stems.fetch(key, []).find { !found.key?(it) }
                    found[after] = name if after && !found.value?(name)
                end
            end

            # {key => the after-names that key pairs}.
            def stems_of(names, real)
                names.each_with_object({}) do |name, stems|
                    key = key_of(name, real, after: true) or next
                    (stems[key] ||= []) << name
                end
            end

            # The key an after-name or a before-name is paired by, or nil.
            def key_of(name, real, after:)
                dir, _, base = name.rpartition("/")
                before = base.downcase.start_with?(BEFORE)
                return if before == after || kind(name) == "text"
                return unless real[name]

                stem = Terms.stem(base)
                [dir, if after
                          stem.sub(ITEM_CODE, "").downcase
                      else
                          stem[BEFORE.length..].downcase
                      end]
            end
        end
    end
end
