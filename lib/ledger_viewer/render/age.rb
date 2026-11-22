# frozen_string_literal: true

module LedgerViewer
    module Render
        # A text drawn from the current time alone (a wait age, "today"):
        # the page script compares a part with its next rendering without
        # it, and updates it in place. Its helpers return plain strings
        # that are escaped, split and quoted on their way into the page,
        # so the age is bracketed by two private-use characters that pass
        # through all of that untouched; the page's body then turns them
        # into <span data-age>, and drops them inside a tag, where an
        # element cannot go.
        module Age
            OPEN = "\u{E000}"
            CLOSE = "\u{E001}"
            MARKS = /[#{OPEN}#{CLOSE}]/o
            TAG = /(<[^>]*>)/

            module_function

            # TEXT bracketed as an age; "" stays "", with nothing to mark.
            def of(text)
                text = text.to_s
                text.empty? ? text : "#{OPEN}#{text}#{CLOSE}"
            end

            # HTML with each bracketed age as <span data-age>.
            def mark(html)
                html.split(TAG).map do |part|
                    next strip(part) if part.start_with?("<")

                    part.gsub(OPEN, "<span data-age>").gsub(CLOSE, "</span>")
                end.join
            end

            # TEXT without the brackets, for a place that holds no markup.
            def strip(text) = text.to_s.gsub(MARKS, "")
        end
    end
end
