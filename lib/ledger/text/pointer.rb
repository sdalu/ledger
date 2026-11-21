# frozen_string_literal: true

module Ledger
    module Text
        # Where a fact was found or a constraint said: a URL, a path
        # (optionally :line or :line-line), "turn …", or free text. Every
        # form is accepted; the kind only says how the viewer draws it.
        #
        #     Ledger::Text::Pointer.kind("lib/x.rb:12-20")   # => "path"
        #     Ledger::Text::Pointer.kind("turn 6")           # => "turn"
        module Pointer
            URL = %r{\Ahttps?://\S+\z}
            LINES = /:[0-9]+(?:-[0-9]+)?\z/
            EXTENSION = /\.[A-Za-z][A-Za-z0-9]*\z/
            TURN = /\Aturn\b.*\S/

            module_function

            # "url", "path", "turn" or "text".
            def kind(text)
                text = text.to_s.strip
                if URL.match?(text) then "url"
                elsif path?(text) then "path"
                elsif TURN.match?(text) then "turn"
                else "text"
                end
            end

            # One word holding a / or ending with a file extension, before
            # its :line.
            def path?(text)
                return false if text.empty? || text.match?(/\s/)

                base = text.sub(LINES, "")
                base.include?("/") || EXTENSION.match?(base)
            end

            # What JSON v1 adds to a fact row: its pointer's kind.
            def of_fact(row) = { pointer_kind: kind(row[:pointer]) }

            # What JSON v1 adds to a constraint row: its where and kind,
            # both nil when its line is not `"QUOTE" — WHERE`.
            def of_constraint(row)
                found = where(row[:text], row[:quote])
                { where: found, where_kind: found && kind(found) }
            end

            # A constraint's where: its line after `"QUOTE" — `, or nil
            # when the line has another shape.
            def where(text, quote)
                head = "\"#{quote}\" — "
                return unless text.to_s.start_with?(head)

                rest = text.to_s.delete_prefix(head).strip
                rest unless rest.empty?
            end
        end
    end
end
