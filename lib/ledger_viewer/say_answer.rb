# frozen_string_literal: true

module LedgerViewer
    # The answer to a question, and what a send says it replaces.
    module SayAnswer
        private

        def answer(ref, fields)
            asked = @data["questions"].reverse_each.find { it["id"] == ref } or
                refuse(409, "#{ref} is no longer asked in this ledger; " \
                            "send it as a note.")
            drop = @form["word"] == "drop"
            prepared!(ref, asked, drop)
            replaces!(fields, ref, :answer)
            fields["word"] = "drop" if drop
            choose(ref, fields, drop ? [] : Render::Reading.options(asked),
                   drop ? [] : asked["items"])
        end

        # A question still being prepared is not answered, but dropped.
        def prepared!(ref, asked, drop)
            return if drop || asked["preparing"].nil?

            refuse(409, "#{ref} is still being prepared by " \
                        "#{asked["preparing"]}; send a note if it cannot " \
                        "wait.")
        end

        def choose(ref, fields, options, items)
            choice = @form["choice"]
            if items.empty?
                single(fields, choice, ref, options)
            else
                per_item(fields, choice, ref, options, items)
            end
            notes = notes_for(items.empty? ? options : items)
            fields["notes"] = notes unless notes.empty?
        end

        # A comment per choice (or per item), those that say something.
        def notes_for(keys)
            keys.to_h { |key| [key, clean(@form["note:#{key}"])] }
                .reject { |_, note| note.empty? }
        end

        def single(fields, choice, ref, options)
            return if choice.empty?

            unless options.include?(choice)
                refuse(400, "#{py_repr(choice)} is not one of " \
                            "#{ref}'s choices.")
            end
            fields["choice"] = choice
        end

        # One answer per item, a comment per item.
        def per_item(fields, choice, ref, options, items)
            picks = items.to_h { [it, @form["pick:#{it}"]] }
                         .reject { |_, pick| pick.empty? }
            unless choice.empty? && picks.values.all? { options.include?(it) }
                refuse(400, "#{ref} takes one of #{options.join(", ")} " \
                            "per item.")
            end
            fields["picks"] = picks unless picks.empty?
        end

        # A string as the messages quote it: single quotes, double when it
        # holds one and no double, backslash escapes.
        def py_repr(text)
            quote = text.include?("'") && !text.include?('"') ? '"' : "'"
            body = text.gsub(/[\\\n\r\t#{quote}\x00-\x1f\x7f]/) do |char|
                escape_for_repr(char)
            end
            "#{quote}#{body}#{quote}"
        end

        def escape_for_repr(char)
            { "\\" => "\\\\", "\n" => "\\n", "\r" => "\\r", "\t" => "\\t",
              "'" => "\\'", '"' => '\\"' }
                .fetch(char) { format("\\x%<code>02x", code: char.ord) }
        end
    end
end
